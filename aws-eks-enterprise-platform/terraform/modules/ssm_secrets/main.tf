###############################################################################
# SSM Secrets — Parameter Store + External Secrets Operator IRSA
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── SSM Parameters ────────────────────────────────────────────────────────────
resource "aws_ssm_parameter" "main" {
  for_each = var.secrets

  name        = "/${var.name_prefix}/${var.environment}/${each.key}"
  type        = "SecureString"
  value       = each.value.value
  description = each.value.description
  key_id      = var.kms_key_arn
  tier        = length(each.value.value) > 4096 ? "Advanced" : "Standard"

  tags = merge(var.tags, { SecretName = each.key })

  lifecycle {
    ignore_changes = [value] # Managed externally after initial creation
  }
}

# ── IAM Read Policy ───────────────────────────────────────────────────────────
resource "aws_iam_policy" "ssm_read" {
  name        = "${var.name_prefix}-ssm-read-policy"
  description = "Read SSM parameters under /${var.name_prefix}/${var.environment}/*"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:DescribeParameters"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.name_prefix}/${var.environment}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = var.kms_key_arn
      }
    ]
  })

  tags = var.tags
}

# ── IAM Write Policy (for CI role) ───────────────────────────────────────────
resource "aws_iam_policy" "ssm_write" {
  count       = var.enable_write_policy ? 1 : 0
  name        = "${var.name_prefix}-ssm-write-policy"
  description = "Write SSM parameters under /${var.name_prefix}/${var.environment}/*"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:DescribeParameters",
          "ssm:AddTagsToResource"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.name_prefix}/${var.environment}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = var.kms_key_arn
      }
    ]
  })

  tags = var.tags
}

# ── Attach read policy to workload IRSA roles ─────────────────────────────────
resource "aws_iam_role_policy_attachment" "workload_ssm_read" {
  count      = length(var.workload_role_arns)
  role       = element(split("/", var.workload_role_arns[count.index]), length(split("/", var.workload_role_arns[count.index])) - 1)
  policy_arn = aws_iam_policy.ssm_read.arn
}

# ── IRSA Role for External Secrets Operator ───────────────────────────────────
resource "aws_iam_role" "eso" {
  count = var.oidc_provider_arn != null ? 1 : 0
  name  = "${var.name_prefix}-eso-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:external-secrets:external-secrets-sa"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eso_ssm_read" {
  count      = var.oidc_provider_arn != null ? 1 : 0
  role       = aws_iam_role.eso[0].name
  policy_arn = aws_iam_policy.ssm_read.arn
}
