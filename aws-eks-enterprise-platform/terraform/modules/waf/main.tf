###############################################################################
# WAF — AWS WAFv2 Web ACL (CLOUDFRONT or REGIONAL scope)
###############################################################################

locals {
  action_block = var.waf_mode == "BLOCK" ? [{}] : []
  action_count = var.waf_mode == "COUNT" ? [{}] : []
}

resource "aws_wafv2_web_acl" "main" {
  name        = "${var.name_prefix}-waf"
  description = "${var.name_prefix} WAF — ${var.scope}"
  scope       = var.scope

  default_action {
    allow {}
  }

  # ── AWS Managed: Common Rule Set ─────────────────────────────────────────
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      dynamic "none" { for_each = local.action_block; content {} }
      dynamic "count" { for_each = local.action_count; content {} }
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # ── AWS Managed: Known Bad Inputs ────────────────────────────────────────
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20
    override_action {
      dynamic "none" { for_each = local.action_block; content {} }
      dynamic "count" { for_each = local.action_count; content {} }
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # ── AWS Managed: SQLi ────────────────────────────────────────────────────
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 30
    override_action {
      dynamic "none" { for_each = local.action_block; content {} }
      dynamic "count" { for_each = local.action_count; content {} }
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-sqli"
      sampled_requests_enabled   = true
    }
  }

  # ── AWS Managed: IP Reputation ───────────────────────────────────────────
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 40
    override_action {
      dynamic "none" { for_each = local.action_block; content {} }
      dynamic "count" { for_each = local.action_count; content {} }
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # ── Rate Limit ───────────────────────────────────────────────────────────
  rule {
    name     = "RateLimitPerIP"
    priority = 50

    action {
      dynamic "block" { for_each = local.action_block; content {} }
      dynamic "count" { for_each = local.action_count; content {} }
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "FORWARDED_IP"  # real client IP from X-Forwarded-For (behind CloudFront)
        forwarded_ip_config {
          header_name       = "X-Forwarded-For"
          fallback_behavior = "MATCH"  # rate-limit if no XFF header (direct hits)
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # ── AWS Managed: Linux OS Rule Set ────────────────────────────────────────
  # Blocks path traversal (../../), command injection via URL paths on Linux
  rule {
    name     = "AWSManagedRulesLinuxRuleSet"
    priority = 55
    override_action {
      dynamic "none" { for_each = local.action_block; content {} }
      dynamic "count" { for_each = local.action_count; content {} }
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesLinuxRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-linux-rules"
      sampled_requests_enabled   = true
    }
  }

  # ── AWS Managed: Unix OS Rule Set ─────────────────────────────────────────
  # Blocks Unix shell metacharacters and OS-level command injection patterns
  rule {
    name     = "AWSManagedRulesUnixRuleSet"
    priority = 57
    override_action {
      dynamic "none" { for_each = local.action_block; content {} }
      dynamic "count" { for_each = local.action_count; content {} }
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesUnixRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-unix-rules"
      sampled_requests_enabled   = true
    }
  }

  # ── AWS Managed: Bot Control ──────────────────────────────────────────────
  # Detects and mitigates L7 bot floods, credential stuffing, and scraping.
  # Challenge/CAPTCHA actions available; COUNT in dev, BLOCK in prod/staging.
  dynamic "rule" {
    for_each = var.enable_bot_control ? [1] : []
    content {
      name     = "AWSManagedRulesBotControlRuleSet"
      priority = 5  # evaluated before all other rules

      override_action {
        dynamic "none" { for_each = local.action_block; content {} }
        dynamic "count" { for_each = local.action_count; content {} }
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesBotControlRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-bot-control"
        sampled_requests_enabled   = true
      }
    }
  }

  # ── Geo Block ────────────────────────────────────────────────────────────
  dynamic "rule" {
    for_each = length(var.blocked_countries) > 0 ? [1] : []
    content {
      name     = "GeoBlockList"
      priority = 60

      action {
        block {}
      }

      statement {
        geo_match_statement {
          country_codes = var.blocked_countries
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-geo-block"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-waf" })
}

# ── Associate with ALB (REGIONAL only) ───────────────────────────────────────
resource "aws_wafv2_web_acl_association" "alb" {
  count        = var.scope == "REGIONAL" && var.alb_arn != null ? 1 : 0
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# ── Logging Configuration ─────────────────────────────────────────────────────
resource "aws_wafv2_web_acl_logging_configuration" "main" {
  count                   = var.s3_logs_bucket_arn != null ? 1 : 0
  log_destination_configs = [var.s3_logs_bucket_arn]
  resource_arn            = aws_wafv2_web_acl.main.arn
}
