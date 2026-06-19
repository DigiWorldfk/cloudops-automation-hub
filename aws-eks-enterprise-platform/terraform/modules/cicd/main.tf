data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── GitHub Actions OIDC Provider ──────────────────────────────────────────────
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  tags            = var.tags
}

# ── GitHub Actions IAM Role ───────────────────────────────────────────────────
resource "aws_iam_role" "github_actions" {
  name = "${var.name_prefix}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

# ── ECR Push/Pull Policy ──────────────────────────────────────────────────────
resource "aws_iam_role_policy" "ecr" {
  count = length(var.ecr_repository_arns) > 0 ? 1 : 0
  name  = "${var.name_prefix}-ci-ecr-policy"
  role  = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage", "ecr:PutImage", "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:DescribeRepositories",
          "ecr:ListImages", "ecr:DescribeImages"
        ]
        Resource = var.ecr_repository_arns
      }
    ]
  })
}

# ── EKS Access Policy ─────────────────────────────────────────────────────────
resource "aws_iam_role_policy" "eks" {
  name = "${var.name_prefix}-ci-eks-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "eks:DescribeCluster", "eks:ListClusters",
        "eks:AccessKubernetesApi"
      ]
      Resource = "arn:aws:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.eks_cluster_name}"
    }]
  })
}

# ── SSM Write Policy (for image tag updates) ─────────────────────────────────
resource "aws_iam_role_policy" "ssm_write" {
  count = var.ssm_parameter_prefix != null ? 1 : 0
  name  = "${var.name_prefix}-ci-ssm-write-policy"
  role  = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:PutParameter", "ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
      Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_parameter_prefix}/*"
    }]
  })
}
