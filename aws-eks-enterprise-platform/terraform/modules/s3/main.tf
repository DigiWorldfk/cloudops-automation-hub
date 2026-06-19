###############################################################################
# S3 — Four buckets: remote-state, app-data, logs, velero-backups
###############################################################################

locals {
  buckets = {
    state   = { versioning = true,  lifecycle_days = 365, object_lock = true  }
    data    = { versioning = true,  lifecycle_days = 365, object_lock = false }
    logs    = { versioning = false, lifecycle_days = var.log_retention_days, object_lock = true  }
    velero  = { versioning = true,  lifecycle_days = 365, object_lock = false }
  }
}

resource "aws_s3_bucket" "main" {
  for_each      = local.buckets
  bucket        = "${var.name_prefix}-${each.key}"
  force_destroy = var.force_destroy
  # Object Lock requires this to be set at bucket creation; versioning is auto-enabled by Object Lock
  object_lock_enabled = each.value.object_lock
  tags          = merge(var.tags, { Name = "${var.name_prefix}-${each.key}" })
}

resource "aws_s3_bucket_versioning" "main" {
  for_each = { for k, v in local.buckets : k => v if v.versioning }
  bucket   = aws_s3_bucket.main[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# ── Object Lock (COMPLIANCE mode on logs + state) ────────────────────────────────
# Prevents CloudTrail log and Terraform state tampering — even by IAM root/admin.
# COMPLIANCE mode cannot be overridden (GOVERNANCE mode can be overridden by root).
resource "aws_s3_bucket_object_lock_configuration" "immutable" {
  for_each   = { for k, v in local.buckets : k => v if v.object_lock }
  bucket     = aws_s3_bucket.main[each.key].id
  depends_on = [aws_s3_bucket_versioning.main]

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 365
    }
  }
}

# ── Object Lock (compliance mode on logs + state) ───────────────────────────────────
# Prevents CloudTrail log and Terraform state tampering, even by root/admin IAM
resource "aws_s3_bucket_object_lock_configuration" "immutable" {
  for_each   = toset(["logs", "state"])
  bucket     = aws_s3_bucket.main[each.key].id
  depends_on = [aws_s3_bucket_versioning.main]

  rule {
    default_retention {
      mode = "COMPLIANCE"  # cannot be overridden even by root — GOVERNANCE would allow root override
      days = 365
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.main[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  for_each                = local.buckets
  bucket                  = aws_s3_bucket.main[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "deny_non_https" {
  for_each   = local.buckets
  bucket     = aws_s3_bucket.main[each.key].id
  depends_on = [aws_s3_bucket_public_access_block.main]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyNonHTTPS"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.main[each.key].arn,
        "${aws_s3_bucket.main[each.key].arn}/*"
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "main" {
  for_each   = local.buckets
  bucket     = aws_s3_bucket.main[each.key].id
  depends_on = [aws_s3_bucket_versioning.main]

  rule {
    id     = "transition-and-expire"
    status = "Enabled"

    filter { prefix = "" }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = each.value.lifecycle_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ── CloudTrail bucket policy ──────────────────────────────────────────────────
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket     = aws_s3_bucket.main["logs"].id
  depends_on = [aws_s3_bucket_public_access_block.main, aws_s3_bucket_policy.deny_non_https]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.main["logs"].arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.main["logs"].arn}/AWSLogs/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}
