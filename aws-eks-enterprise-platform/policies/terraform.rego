###############################################################################
# OPA / conftest — AWS Terraform security policies
###############################################################################

package main

import future.keywords.if
import future.keywords.in

# ── RDS encryption ───────────────────────────────────────────────────────────
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_rds_cluster"
  not r.change.after.storage_encrypted
  msg := sprintf("DENY: RDS cluster '%s' must have storage_encrypted = true", [r.address])
}

# ── S3 no public access ──────────────────────────────────────────────────────
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_s3_bucket_public_access_block"
  not r.change.after.block_public_acls
  msg := sprintf("DENY: S3 bucket '%s' must have block_public_acls = true", [r.address])
}

deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_s3_bucket_public_access_block"
  not r.change.after.restrict_public_buckets
  msg := sprintf("DENY: S3 bucket '%s' must have restrict_public_buckets = true", [r.address])
}

# ── S3 HTTPS enforce ─────────────────────────────────────────────────────────
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_s3_bucket"
  r.change.after_unknown != {}
  not bucket_has_https_policy(r.change.after.bucket)
  msg := sprintf("WARN: S3 bucket '%s' should enforce HTTPS via bucket policy", [r.address])
}

bucket_has_https_policy(_) := false

# ── KMS key rotation ─────────────────────────────────────────────────────────
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_kms_key"
  not r.change.after.enable_key_rotation
  msg := sprintf("DENY: KMS key '%s' must have enable_key_rotation = true", [r.address])
}

# ── EKS endpoint not fully public in prod ────────────────────────────────────
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_eks_cluster"
  r.change.after.tags.environment == "prod"
  r.change.after.vpc_config[0].endpoint_public_access == true
  r.change.after.vpc_config[0].endpoint_private_access == false
  msg := sprintf("DENY: EKS cluster '%s' in prod must not have endpoint_public_access = true without endpoint_private_access", [r.address])
}

# ── GuardDuty must be enabled ─────────────────────────────────────────────────
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_guardduty_detector"
  not r.change.after.enable
  msg := sprintf("DENY: GuardDuty detector '%s' must have enable = true", [r.address])
}

# ── ECR scanning on push in prod ─────────────────────────────────────────────
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_ecr_repository"
  r.change.after.tags.environment == "prod"
  not r.change.after.image_scanning_configuration[0].scan_on_push
  msg := sprintf("DENY: ECR repository '%s' in prod must have scan_on_push = true", [r.address])
}

# ── SSM SecureString must use KMS (not default SSM key) ──────────────────────
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_ssm_parameter"
  r.change.after.type == "SecureString"
  not r.change.after.key_id
  msg := sprintf("DENY: SSM parameter '%s' SecureString must use a customer-managed KMS key (key_id must be set)", [r.address])
}

# ── SSM String must not hold sensitive-sounding values ───────────────────────
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_ssm_parameter"
  r.change.after.type == "String"
  name := r.change.after.name
  contains_sensitive_word(name)
  msg := sprintf("DENY: SSM parameter '%s' appears to hold sensitive data but is type String — use SecureString", [r.address])
}

contains_sensitive_word(name) if { contains(name, "password") }
contains_sensitive_word(name) if { contains(name, "secret") }
contains_sensitive_word(name) if { contains(name, "token") }
contains_sensitive_word(name) if { contains(name, "key") }

# ── Security Group — no 0.0.0.0/0 ingress on sensitive ports ────────────────
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_security_group"
  ingress := r.change.after.ingress[_]
  ingress.cidr_blocks[_] == "0.0.0.0/0"
  sensitive_port(ingress.from_port)
  msg := sprintf("DENY: Security group '%s' has 0.0.0.0/0 ingress on sensitive port %d", [r.address, ingress.from_port])
}

sensitive_port(p) if { p == 22 }
sensitive_port(p) if { p == 3306 }
sensitive_port(p) if { p == 5432 }
sensitive_port(p) if { p == 6379 }

# ── RDS deletion protection in prod ──────────────────────────────────────────
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_rds_cluster"
  r.change.after.tags.environment == "prod"
  not r.change.after.deletion_protection
  msg := sprintf("DENY: RDS cluster '%s' in prod must have deletion_protection = true", [r.address])
}

# ── Internal NLB SG — no 0.0.0.0/0 ingress on database ports ─────────────────
# The nlb_internal module uses SG-to-SG rules only; a 0.0.0.0/0 ingress on a
# database port would mean the module's security intent has been bypassed.
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_security_group"
  contains(r.change.after.name, "nlb-internal")
  ingress := r.change.after.ingress[_]
  ingress.cidr_blocks[_] == "0.0.0.0/0"
  db_port(ingress.from_port)
  msg := sprintf(
    "DENY: Internal NLB SG '%s' must not allow 0.0.0.0/0 ingress on database port %d — use SG-to-SG rules only",
    [r.address, ingress.from_port],
  )
}

deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_security_group"
  contains(r.change.after.name, "nlb-internal")
  ingress := r.change.after.ingress[_]
  ingress.ipv6_cidr_blocks[_] == "::/0"
  db_port(ingress.from_port)
  msg := sprintf(
    "DENY: Internal NLB SG '%s' must not allow ::/0 ingress on database port %d — use SG-to-SG rules only",
    [r.address, ingress.from_port],
  )
}

db_port(p) if { p == 5432 }
db_port(p) if { p == 3306 }

# ── ALB must drop invalid header fields ───────────────────────────────────────────────────────
# Prevents HTTP request-smuggling attacks via malformed Transfer-Encoding/Content-Length
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_lb"
  r.change.after.load_balancer_type == "application"
  not r.change.after.drop_invalid_header_fields
  msg := sprintf("DENY: ALB '%s' must have drop_invalid_header_fields = true to prevent HTTP request smuggling", [r.address])
}

# ── CloudFront must have WAF attached in prod ───────────────────────────────────────────
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_cloudfront_distribution"
  r.change.after.tags.environment == "prod"
  not r.change.after.web_acl_id
  msg := sprintf("DENY: CloudFront distribution '%s' in prod must have a WAF Web ACL attached (web_acl_id)", [r.address])
}

# ── CloudFront default_cache_behavior must have response headers policy ──────────────
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_cloudfront_distribution"
  not r.change.after.default_cache_behavior[0].response_headers_policy_id
  msg := sprintf("DENY: CloudFront distribution '%s' must attach a response_headers_policy_id (HSTS, X-Frame-Options, etc.)", [r.address])
}

# ── EKS public endpoint must not allow 0.0.0.0/0 ───────────────────────────────────────
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_eks_cluster"
  r.change.after.vpc_config[0].endpoint_public_access == true
  r.change.after.vpc_config[0].public_access_cidrs[_] == "0.0.0.0/0"
  msg := sprintf("DENY: EKS cluster '%s' has endpoint_public_access = true with 0.0.0.0/0 — restrict public_access_cidrs to known CIDRs", [r.address])
}

# ── RDS must have IAM database authentication enabled in prod ───────────────────────
deny[msg] if {
  r := input.resource_changes[_]
  r.type == "aws_rds_cluster"
  r.change.after.tags.environment == "prod"
  not r.change.after.iam_database_authentication_enabled
  msg := sprintf("DENY: RDS cluster '%s' in prod must have iam_database_authentication_enabled = true", [r.address])
}
