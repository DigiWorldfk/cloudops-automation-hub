###############################################################################
# VPC — core network fabric
###############################################################################

locals {
  # Use 1 NAT GW in dev/staging (single_nat_gateway=true), one per AZ in prod
  nat_gateway_count = var.single_nat_gateway ? 1 : length(var.availability_zones)
}

# ── VPC ───────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

# ── Public Subnets ────────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                          = "${var.name_prefix}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${var.name_prefix}"    = "shared"
  })
}

# ── Private Subnets (EKS nodes) ───────────────────────────────────────────────
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name                                          = "${var.name_prefix}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${var.name_prefix}"    = "shared"
  })
}

# ── Isolated Subnets (RDS / ElastiCache) ─────────────────────────────────────
resource "aws_subnet" "isolated" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.isolated_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-isolated-${var.availability_zones[count.index]}"
  })
}

# ── Elastic IPs + NAT Gateways ────────────────────────────────────────────────
resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name_prefix}-eip-nat-${count.index}" })
}

resource "aws_nat_gateway" "main" {
  count         = local.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags       = merge(var.tags, { Name = "${var.name_prefix}-natgw-${count.index}" })
  depends_on = [aws_internet_gateway.main]
}

# ── Route Tables ──────────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(var.tags, { Name = "${var.name_prefix}-rt-public" })
}

resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id
  }

  dynamic "route" {
    for_each = var.enable_transit_gateway ? var.tgw_destination_cidrs : []
    content {
      cidr_block         = route.value
      transit_gateway_id = var.enable_transit_gateway ? (var.transit_gateway_id != null ? var.transit_gateway_id : aws_ec2_transit_gateway.main[0].id) : null
    }
  }

  dynamic "route" {
    for_each = var.enable_vpn ? var.vpn_destination_cidrs : []
    content {
      cidr_block = route.value
      gateway_id = var.enable_vpn ? aws_vpn_gateway.main[0].id : null
    }
  }

  dynamic "route" {
    for_each = var.enable_vpc_peering && var.peer_vpc_cidr != null ? [var.peer_vpc_cidr] : []
    content {
      cidr_block                = route.value
      vpc_peering_connection_id = aws_vpc_peering_connection.main[0].id
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-rt-private-${var.availability_zones[count.index]}" })
}

resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-rt-isolated" })
}

resource "aws_route_table_association" "isolated" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated.id
}

# ── VPC Flow Logs ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${var.name_prefix}/flow-logs"
  retention_in_days = var.environment == "prod" ? 90 : 30
  tags              = var.tags
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${var.name_prefix}-vpc-flow-logs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${var.name_prefix}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup", "logs:CreateLogStream",
        "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
  tags            = merge(var.tags, { Name = "${var.name_prefix}-flow-log" })
}

###############################################################################
# Network ACLs — subnet-level defence-in-depth (separate failure domain from SGs)
###############################################################################

# Public subnets — only allow HTTP/HTTPS inbound; return traffic via ephemeral ports
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.public[*].id
  tags       = merge(var.tags, { Name = "${var.name_prefix}-nacl-public" })

  ingress {
    rule_no    = 100; protocol = "tcp"; action = "allow"
    cidr_block = "0.0.0.0/0"; from_port = 80; to_port = 80
  }
  ingress {
    rule_no    = 110; protocol = "tcp"; action = "allow"
    cidr_block = "0.0.0.0/0"; from_port = 443; to_port = 443
  }
  ingress {
    rule_no    = 120; protocol = "tcp"; action = "allow"  # ephemeral return traffic
    cidr_block = "0.0.0.0/0"; from_port = 1024; to_port = 65535
  }
  egress {
    rule_no    = 100; protocol = "-1"; action = "allow"
    cidr_block = "0.0.0.0/0"; from_port = 0; to_port = 0
  }
}

# Private subnets (EKS nodes) — allow inbound from VPC only
resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id
  tags       = merge(var.tags, { Name = "${var.name_prefix}-nacl-private" })

  ingress {
    rule_no    = 100; protocol = "-1"; action = "allow"
    cidr_block = var.vpc_cidr; from_port = 0; to_port = 0
  }
  ingress {
    rule_no    = 200; protocol = "tcp"; action = "allow"  # ephemeral return from internet (via NAT)
    cidr_block = "0.0.0.0/0"; from_port = 1024; to_port = 65535
  }
  egress {
    rule_no    = 100; protocol = "-1"; action = "allow"
    cidr_block = "0.0.0.0/0"; from_port = 0; to_port = 0
  }
}

# Isolated subnets (RDS) — allow 5432 from private CIDR only, nothing else
resource "aws_network_acl" "isolated" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.isolated[*].id
  tags       = merge(var.tags, { Name = "${var.name_prefix}-nacl-isolated" })

  ingress {
    rule_no    = 100; protocol = "tcp"; action = "allow"
    cidr_block = var.vpc_cidr; from_port = 5432; to_port = 5432
  }
  ingress {
    rule_no    = 110; protocol = "tcp"; action = "allow"  # MySQL
    cidr_block = var.vpc_cidr; from_port = 3306; to_port = 3306
  }
  egress {
    rule_no    = 100; protocol = "tcp"; action = "allow"  # ephemeral return
    cidr_block = var.vpc_cidr; from_port = 1024; to_port = 65535
  }
}

# ── VPC Peering ───────────────────────────────────────────────────────────────
resource "aws_vpc_peering_connection" "main" {
  count       = var.enable_vpc_peering ? 1 : 0
  vpc_id      = aws_vpc.main.id
  peer_vpc_id = var.peer_vpc_id
  peer_owner_id = var.peer_owner_id
  peer_region = var.peer_region
  auto_accept = false  # always require explicit manual acceptance for security review

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc-peering" })
}

resource "aws_vpc_peering_connection_accepter" "main" {
  count                     = var.enable_vpc_peering && var.peer_region != null ? 1 : 0
  vpc_peering_connection_id = aws_vpc_peering_connection.main[0].id
  auto_accept               = true
  tags                      = merge(var.tags, { Name = "${var.name_prefix}-vpc-peering-accepter" })
}

# ── Transit Gateway ───────────────────────────────────────────────────────────
resource "aws_ec2_transit_gateway" "main" {
  count                           = var.enable_transit_gateway && var.transit_gateway_id == null ? 1 : 0
  description                     = "${var.name_prefix} Transit Gateway — hub-and-spoke"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  auto_accept_shared_attachments  = "disable"  # require explicit RAM resource share acceptance
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(var.tags, { Name = "${var.name_prefix}-tgw" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "main" {
  count              = var.enable_transit_gateway ? 1 : 0
  transit_gateway_id = var.transit_gateway_id != null ? var.transit_gateway_id : aws_ec2_transit_gateway.main[0].id
  vpc_id             = aws_vpc.main.id
  subnet_ids         = aws_subnet.private[*].id

  tags = merge(var.tags, { Name = "${var.name_prefix}-tgw-attachment" })
}

# ── Site-to-Site VPN ──────────────────────────────────────────────────────────
resource "aws_customer_gateway" "main" {
  count      = var.enable_vpn ? 1 : 0
  bgp_asn    = var.customer_gateway_bgp_asn
  ip_address = var.customer_gateway_ip
  type       = "ipsec.1"
  tags       = merge(var.tags, { Name = "${var.name_prefix}-cgw" })
}

resource "aws_vpn_gateway" "main" {
  count  = var.enable_vpn ? 1 : 0
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-vgw" })
}

resource "aws_vpn_connection" "main" {
  count               = var.enable_vpn ? 1 : 0
  customer_gateway_id = aws_customer_gateway.main[0].id
  vpn_gateway_id      = aws_vpn_gateway.main[0].id
  type                = "ipsec.1"
  static_routes_only  = false # BGP enabled

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpn" })
}

resource "aws_vpn_gateway_route_propagation" "private" {
  count          = var.enable_vpn ? length(var.availability_zones) : 0
  vpn_gateway_id = aws_vpn_gateway.main[0].id
  route_table_id = aws_route_table.private[count.index].id
}
