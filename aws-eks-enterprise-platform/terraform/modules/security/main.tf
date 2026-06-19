###############################################################################
# Security — KMS keys, GuardDuty, Security Hub, CloudTrail, IRSA policies
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── KMS Keys ──────────────────────────────────────────────────────────────────
locals {
  kms_services = ["eks", "ebs", "rds", "s3", "ssm", "secrets"]
}

resource "aws_kms_key" "main" {
  for_each                = toset(local.kms_services)
  description             = "${var.name_prefix} KMS key for ${each.key}"
  deletion_window_in_days = var.environment == "prod" ? 30 : 7
  enable_key_rotation     = true
  multi_region            = contains(["rds", "secrets"], each.key)  # enable cross-region replica for DR

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootAdminAccess"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action   = ["kms:Describe*", "kms:List*", "kms:Get*", "kms:Create*", "kms:Delete*",
                    "kms:DisableKey", "kms:EnableKey", "kms:PutKeyPolicy", "kms:ScheduleKeyDeletion",
                    "kms:TagResource", "kms:UntagResource", "kms:UpdateAlias", "kms:CreateAlias",
                    "kms:DeleteAlias", "kms:UpdateKeyDescription", "kms:ReplicateKey",
                    "kms:CreateGrant", "kms:RetireGrant", "kms:RevokeGrant"]
        Resource = "*"
      },
      {
        Sid    = "ServiceEncryptDecrypt"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action   = ["kms:GenerateDataKey*", "kms:Decrypt", "kms:Encrypt", "kms:ReEncrypt*"]
        Resource = "*"
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

# ── GuardDuty ─────────────────────────────────────────────────────────────────
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs { enable = true }
    kubernetes {
      audit_logs { enable = true }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes { enable = true }
      }
    }
  }

  tags = var.tags
}

# ── Security Hub ──────────────────────────────────────────────────────────────
resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "cis" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.4.0"
}

resource "aws_securityhub_standards_subscription" "foundational" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

# ── CloudTrail ────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.name_prefix}"
  retention_in_days = var.environment == "prod" ? 365 : 90
  kms_key_id        = aws_kms_key.main["eks"].arn
  tags              = var.tags
}

resource "aws_iam_role" "cloudtrail" {
  name = "${var.name_prefix}-cloudtrail-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "cloudtrail" {
  name = "${var.name_prefix}-cloudtrail-policy"
  role = aws_iam_role.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "${var.name_prefix}-trail"
  s3_bucket_name                = var.cloudtrail_s3_bucket
  include_global_service_events = true
  is_multi_region_trail         = var.environment == "prod"
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail.arn
  kms_key_id                    = aws_kms_key.main["eks"].arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-trail" })
}

# ── IRSA Policies ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "irsa" {
  for_each = var.irsa_service_accounts

  name = "${var.name_prefix}-irsa-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.tags, { ServiceAccount = each.value.service_account })
}

resource "aws_iam_role_policy" "irsa" {
  for_each = var.irsa_service_accounts
  name     = "${var.name_prefix}-irsa-${each.key}-policy"
  role     = aws_iam_role.irsa[each.key].id
  policy   = each.value.policy_json
}

###############################################################################
# GuardDuty Findings — S3 Export + SNS High-Severity Alerting
###############################################################################

resource "aws_guardduty_publishing_destination" "findings" {
  count        = var.cloudtrail_s3_bucket != null ? 1 : 0
  detector_id  = aws_guardduty_detector.main.id
  destination_type = "S3"
  destination_arn  = "arn:aws:s3:::${var.cloudtrail_s3_bucket}"
  kms_key_arn      = aws_kms_key.main["s3"].arn
}

resource "aws_sns_topic" "guardduty_alerts" {
  name              = "${var.name_prefix}-guardduty-alerts"
  kms_master_key_id = aws_kms_key.main["ssm"].arn
  tags              = var.tags
}

resource "aws_sns_topic_subscription" "guardduty_email" {
  count     = var.security_alert_email != null ? 1 : 0
  topic_arn = aws_sns_topic.guardduty_alerts.arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}

resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "${var.name_prefix}-guardduty-high-severity"
  description = "Capture GuardDuty findings with severity >= HIGH (7.0+)"
  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_high.name
  target_id = "GuardDutySNS"
  arn       = aws_sns_topic.guardduty_alerts.arn
}
