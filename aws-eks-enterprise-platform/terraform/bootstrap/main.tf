###############################################################################
# Bootstrap — S3 remote state + DynamoDB lock tables (run once manually)
###############################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws"; version = "~> 5.50" }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" { type = string; default = "eu-west-1" }
variable "project" { type = string; default = "eks-enterprise" }
variable "environments" {
  type    = list(string)
  default = ["dev", "staging", "prod"]
}

locals {
  tags = {
    project    = var.project
    managed_by = "terraform-bootstrap"
  }
}

# ── KMS key for state encryption ──────────────────────────────────────────────
resource "aws_kms_key" "state" {
  description             = "${var.project} Terraform state encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = local.tags
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.project}-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

# ── S3 state buckets ──────────────────────────────────────────────────────────
resource "aws_s3_bucket" "state" {
  for_each      = toset(var.environments)
  bucket        = "${var.project}-${each.key}-state"
  force_destroy = false
  tags          = merge(local.tags, { environment = each.key })
}

resource "aws_s3_bucket_versioning" "state" {
  for_each = toset(var.environments)
  bucket   = aws_s3_bucket.state[each.key].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  for_each = toset(var.environments)
  bucket   = aws_s3_bucket.state[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  for_each                = toset(var.environments)
  bucket                  = aws_s3_bucket.state[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "state" {
  for_each   = toset(var.environments)
  bucket     = aws_s3_bucket.state[each.key].id
  depends_on = [aws_s3_bucket_public_access_block.state]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyNonHTTPS"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = ["${aws_s3_bucket.state[each.key].arn}", "${aws_s3_bucket.state[each.key].arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# ── DynamoDB lock tables ──────────────────────────────────────────────────────
resource "aws_dynamodb_table" "lock" {
  for_each     = toset(var.environments)
  name         = "${var.project}-${each.key}-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state.arn
  }

  tags = merge(local.tags, { environment = each.key })
}

output "state_bucket_names" {
  value = { for k, v in aws_s3_bucket.state : k => v.id }
}

output "dynamodb_table_names" {
  value = { for k, v in aws_dynamodb_table.lock : k => v.name }
}
