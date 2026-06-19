###############################################################################
# Internal NLB — Database Tier
#
# Topology
# ─────────
#   EKS Worker Nodes (private subnets)
#       │  TCP:db_port  (SG: eks_node_sg → nlb_sg)
#       ▼
#   [Internal NLB]  ← no public IP, cross-zone LB enabled
#       │  TCP:db_port  (SG: nlb_sg → db_nodes_sg)
#       ▼
#   DB Target Group  (Round-Robin, IP-mode)
#       │
#       ├── 10.x.x.x  (AZ-a  Aurora / Postgres / MySQL)
#       ├── 10.x.x.x  (AZ-b  read replica)
#       └── 10.x.x.x  (AZ-c  read replica)
#
# Security posture
# ─────────────────
#   • NLB SG accepts TCP on db_port ONLY from eks_node_security_group_id
#   • DB-nodes SG accepts TCP on db_port ONLY from nlb_sg (never from internet)
#   • Both SGs deny all else; egress unrestricted (standard AWS pattern)
#   • Health checks run on the same db_port (TCP) — no HTTP probes needed
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

###############################################################################
# Locals
###############################################################################

locals {
  # Resolve effective port from engine default when caller passes 0
  engine_default_ports = {
    postgres = 5432
    mysql    = 3306
  }
  effective_port = var.db_port != 0 ? var.db_port : local.engine_default_ports[var.db_engine]

  # Build a map of IP → AZ for target registration (fallback: no AZ override)
  targets_with_az = length(var.db_target_availability_zones) == length(var.db_target_ips)
  target_list = [
    for i, ip in var.db_target_ips : {
      ip = ip
      az = local.targets_with_az ? var.db_target_availability_zones[i] : null
    }
  ]
}

###############################################################################
# Security Groups
###############################################################################

# ── NLB Security Group ────────────────────────────────────────────────────────
# Accepts DB traffic only from EKS worker-node security group.
resource "aws_security_group" "nlb" {
  name        = "${var.name_prefix}-nlb-internal-sg"
  description = "Internal DB NLB — allow TCP:${local.effective_port} from EKS nodes only"
  vpc_id      = var.vpc_id

  # Ingress: EKS worker nodes → NLB (by SG reference — most restrictive)
  ingress {
    description     = "DB traffic from EKS worker nodes"
    from_port       = local.effective_port
    to_port         = local.effective_port
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
  }

  # Ingress: EKS node subnet CIDRs (defence-in-depth, optional second layer)
  dynamic "ingress" {
    for_each = var.eks_node_subnet_cidrs
    content {
      description = "DB traffic from EKS node subnet CIDR ${ingress.value}"
      from_port   = local.effective_port
      to_port     = local.effective_port
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  # NLB health-check probes originate from within the VPC — allow return traffic
  ingress {
    description = "NLB health-check (VPC internal)"
    from_port   = local.effective_port
    to_port     = local.effective_port
    protocol    = "tcp"
    self        = true
  }

  # Egress: unrestricted (NLB forwards to DB nodes)
  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-nlb-internal-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# ── DB Nodes Security Group ───────────────────────────────────────────────────
# Attach this SG to every database node (EC2, RDS, Aurora instance).
# The ONLY allowed ingress is TCP on db_port from the NLB SG — nothing else.
resource "aws_security_group" "db_nodes" {
  name        = "${var.name_prefix}-db-nodes-sg"
  description = "DB nodes — allow TCP:${local.effective_port} from internal NLB only"
  vpc_id      = var.vpc_id

  # Ingress: NLB → DB nodes (SG-to-SG — zero-blast-radius)
  ingress {
    description     = "DB access via internal NLB only"
    from_port       = local.effective_port
    to_port         = local.effective_port
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb.id]
  }

  # Egress: unrestricted (replication traffic, OS updates, etc.)
  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-nodes-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# Target Group — IP-based, Round-Robin, TCP
###############################################################################

resource "aws_lb_target_group" "db" {
  name                   = "${var.name_prefix}-nlb-db-tg"
  port                   = local.effective_port
  protocol               = "TCP"
  vpc_id                 = var.vpc_id
  target_type            = "ip"                # register DB IPs directly
  load_balancing_algorithm_type = "round_robin" # explicit even though default for NLB

  # Drain connections gracefully before deregistering
  deregistration_delay = var.deregistration_delay

  # ── TCP Health Check ────────────────────────────────────────────────────────
  # A TCP probe on the database port is the most reliable signal — it tests the
  # full network path AND confirms the DB process is accepting connections.
  health_check {
    enabled             = var.health_check_enabled
    protocol            = "TCP"
    port                = "traffic-port"          # same as db_port
    interval            = var.health_check_interval
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    # No path/matcher — TCP probes do not use HTTP attributes
  }

  stickiness {
    enabled = false    # Round-Robin — no sticky sessions for DB tier
    type    = "source_ip"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-nlb-db-tg" })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# Target Registrations — DB IPs
###############################################################################

resource "aws_lb_target_group_attachment" "db" {
  for_each = { for i, t in local.target_list : tostring(i) => t }

  target_group_arn  = aws_lb_target_group.db.arn
  target_id         = each.value.ip
  port              = local.effective_port
  availability_zone = each.value.az
}

###############################################################################
# Internal Network Load Balancer
###############################################################################

resource "aws_lb" "internal_db" {
  name               = "${var.name_prefix}-nlb-db"
  internal           = true                   # never publicly reachable
  load_balancer_type = "network"
  subnets            = var.private_subnet_ids
  security_groups    = [aws_security_group.nlb.id]

  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  enable_deletion_protection       = var.deletion_protection

  # Preserve client IP so DB can log real source addresses for audit
  enable_preserve_client_ip = true

  dynamic "access_logs" {
    for_each = var.access_logs_bucket != null ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = var.access_logs_prefix
      enabled = true
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-nlb-db" })
}

###############################################################################
# Listener — TCP on effective DB port → Target Group
###############################################################################

resource "aws_lb_listener" "db" {
  load_balancer_arn = aws_lb.internal_db.arn
  port              = local.effective_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.db.arn
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-nlb-db-listener" })
}

###############################################################################
# CloudWatch — NLB health alarm
###############################################################################

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.name_prefix}-nlb-db-unhealthy-hosts"
  alarm_description   = "Fires when any DB target is unhealthy — check replication lag or process crash"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/NetworkELB"
  period              = var.health_check_interval * 2
  statistic           = "Maximum"
  threshold           = 0

  dimensions = {
    LoadBalancer = aws_lb.internal_db.arn_suffix
    TargetGroup  = aws_lb_target_group.db.arn_suffix
  }

  treat_missing_data = "notBreaching"

  tags = var.tags
}
