###############################################################################
# EKS — Managed Kubernetes cluster with IRSA + addons
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── IAM — Cluster Role ────────────────────────────────────────────────────────
resource "aws_iam_role" "cluster" {
  name = "${var.name_prefix}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# ── Security Group — Cluster ──────────────────────────────────────────────────
resource "aws_security_group" "cluster" {
  name        = "${var.name_prefix}-eks-cluster-sg"
  description = "EKS cluster control plane — managed by Terraform"
  vpc_id      = var.vpc_id

  # API server → node kubelet + pod communication (within VPC only)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "API server to nodes (HTTPS/443) within VPC"
  }
  egress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Kubelet API (10250) within VPC"
  }
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "CoreDNS TCP within VPC"
  }
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
    description = "CoreDNS UDP within VPC"
  }
  # Allow HTTPS to AWS APIs (ECR, SSM, STS, etc.) via NAT GW
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Outbound HTTPS to AWS APIs and container registries"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-eks-cluster-sg" })
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.name_prefix}/cluster"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = var.name_prefix
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  enabled_cluster_log_types = var.cluster_log_types

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Encrypt Kubernetes Secrets at rest in etcd using a customer-managed KMS key
  encryption_config {
    provider {
      key_arn = var.kms_key_arn
    }
    resources = ["secrets"]
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_policy,
    aws_cloudwatch_log_group.eks,
  ]

  tags = merge(var.tags, { Name = var.name_prefix })
}

# ── OIDC Provider (IRSA) ──────────────────────────────────────────────────────
data "tls_certificate" "eks" {
  count = var.enable_irsa ? 1 : 0
  url   = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  count           = var.enable_irsa ? 1 : 0
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  tags            = var.tags
}

# ── IAM — Node Role ───────────────────────────────────────────────────────────
resource "aws_iam_role" "node" {
  name = "${var.name_prefix}-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ── Managed Node Group ────────────────────────────────────────────────────────
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.node_instance_types
  capacity_type   = var.node_capacity_type
  disk_size       = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable_percentage = 25
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }

  dynamic "taint" {
    for_each = var.environment == "prod" ? [] : []
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
  ]

  tags = merge(var.tags, { Name = "${var.name_prefix}-nodes" })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ── Core Add-ons ──────────────────────────────────────────────────────────────
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = "PRESERVE"  # was OVERWRITE — prevents silent destruction of custom VPC-CNI config
  tags                        = var.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_update = "PRESERVE"  # was OVERWRITE — preserves custom CoreDNS ConfigMap overrides
  depends_on                  = [aws_eks_node_group.main]
  tags                        = var.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "PRESERVE"
  tags                        = var.tags
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_eks_node_group.main]
  tags                        = var.tags
}

# EKS Pod Identity — modern successor to IRSA; provides per-pod AWS credentials
# via the EKS Pod Identity Agent daemonset without requiring OIDC thumbprint mgmt
resource "aws_eks_addon" "pod_identity" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_eks_node_group.main]
  tags                        = var.tags
}
