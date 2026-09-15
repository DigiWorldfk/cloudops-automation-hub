###############################################################################
# KMS — standalone customer-managed keys, one per consuming service.
# Split out from `security` so that `s3` (which needs a key) and `security`
# (which needs s3's bucket for CloudTrail) don't form a dependency cycle.
###############################################################################

data "aws_caller_identity" "current" {}

locals {
  kms_services = ["eks", "ebs", "rds", "s3", "ssm", "secrets"]
}

resource "aws_kms_key" "main" {
  for_each                = toset(local.kms_services)
  description             = "${var.name_prefix} KMS key for ${each.key}"
  deletion_window_in_days = var.environment == "prod" ? 30 : 7
  enable_key_rotation     = true
  multi_region            = contains(["rds", "secrets"], each.key) # enable cross-region replica for DR

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RootAdminAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action = ["kms:Describe*", "kms:List*", "kms:Get*", "kms:Create*", "kms:Delete*",
          "kms:DisableKey", "kms:EnableKey", "kms:PutKeyPolicy", "kms:ScheduleKeyDeletion",
          "kms:TagResource", "kms:UntagResource", "kms:UpdateAlias", "kms:CreateAlias",
          "kms:DeleteAlias", "kms:UpdateKeyDescription", "kms:ReplicateKey",
        "kms:CreateGrant", "kms:RetireGrant", "kms:RevokeGrant"]
        Resource = "*"
      },
      {
        Sid       = "ServiceEncryptDecrypt"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt", "kms:Encrypt", "kms:ReEncrypt*"]
        Resource  = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-kms-${each.key}" })
}

resource "aws_kms_alias" "main" {
  for_each      = toset(local.kms_services)
  name          = "alias/${var.name_prefix}-${each.key}"
  target_key_id = aws_kms_key.main[each.key].key_id
}
