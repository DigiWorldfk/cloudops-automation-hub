###############################################################################
# Domain — Route53 zone + ACM certificates + DNS records
###############################################################################

# ── Route53 Hosted Zone ───────────────────────────────────────────────────────
resource "aws_route53_zone" "main" {
  name = var.domain_name
  tags = merge(var.tags, { Name = "${var.name_prefix}-zone" })
}

# ── ACM Certificate (us-east-1 — for CloudFront) ─────────────────────────────
resource "aws_acm_certificate" "cloudfront" {
  provider                  = aws.us_east_1
  domain_name               = var.domain_name
  subject_alternative_names = concat(["*.${var.domain_name}"], var.subject_alternative_names)
  validation_method         = "DNS"

  lifecycle { create_before_destroy = true }
  tags = merge(var.tags, { Name = "${var.name_prefix}-cert-cf" })
}

resource "aws_route53_record" "cloudfront_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for r in aws_route53_record.cloudfront_cert_validation : r.fqdn]
}

# ── ACM Certificate (regional — for ALB) ─────────────────────────────────────
resource "aws_acm_certificate" "regional" {
  domain_name               = var.domain_name
  subject_alternative_names = concat(["*.${var.domain_name}"], var.subject_alternative_names)
  validation_method         = "DNS"

  lifecycle { create_before_destroy = true }
  tags = merge(var.tags, { Name = "${var.name_prefix}-cert-regional" })
}

resource "aws_acm_certificate_validation" "regional" {
  certificate_arn         = aws_acm_certificate.regional.arn
  validation_record_fqdns = [for r in aws_route53_record.cloudfront_cert_validation : r.fqdn]
}

# ── DNS Records ───────────────────────────────────────────────────────────────

# Apex → CloudFront ALIAS
resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = true
  }
}

# www → CloudFront ALIAS
resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = true
  }
}

# api → CloudFront ALIAS (NOT direct-to-ALB — routes through WAF + CloudFront /api/* behavior)
# The CDN module's /api/* ordered_cache_behavior has TTL=0 (no caching) so API responses
# pass through immediately. This ensures WAF coverage on the highest-risk surface.
resource "aws_route53_record" "api" {
  count   = var.cloudfront_domain_name != null ? 1 : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = true
  }
}

# MX Records
resource "aws_route53_record" "mx" {
  count   = length(var.mx_records) > 0 ? 1 : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "MX"
  ttl     = 300
  records = var.mx_records
}

# SPF
resource "aws_route53_record" "spf" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 300
  records = [var.spf_record]
}

# DMARC
resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 300
  records = ["v=DMARC1; p=${var.dmarc_policy}; rua=mailto:dmarc-reports@${var.domain_name}; ruf=mailto:dmarc-failures@${var.domain_name}; fo=1"]
}
