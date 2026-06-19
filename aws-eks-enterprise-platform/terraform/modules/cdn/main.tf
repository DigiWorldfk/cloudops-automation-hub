###############################################################################
# CDN — CloudFront distribution in front of ALB
###############################################################################

locals {
  all_aliases = concat([var.domain_name], var.aliases)
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.name_prefix} CDN"
  aliases             = local.all_aliases
  price_class         = var.price_class
  web_acl_id          = var.waf_web_acl_arn
  http_version        = "http2and3"
  wait_for_deployment = false

  # ── ALB Origin ────────────────────────────────────────────────────────────
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "${var.name_prefix}-alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 30
      origin_keepalive_timeout = 5
    }

    custom_header {
      name  = "X-CloudFront-Secret"
      value = var.origin_secret
    }
  }

  # ── Default Cache Behavior ─────────────────────────────────────────────────
  default_cache_behavior {
    target_origin_id       = "${var.name_prefix}-alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["Host", "Authorization", "CloudFront-Forwarded-Proto"]
      cookies { forward = "none" }
    }

    default_ttl = var.default_ttl
    max_ttl     = var.max_ttl
    min_ttl     = 0
  }

  # ── Static Assets Cache Behavior ─────────────────────────────────────────
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "${var.name_prefix}-alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    default_ttl = 86400
    max_ttl     = 604800
    min_ttl     = 0
  }

  # ── API Path — no caching ─────────────────────────────────────────────────
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "${var.name_prefix}-alb-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies { forward = "all" }
    }

    default_ttl = 0
    max_ttl     = 0
    min_ttl     = 0
  }

  # ── Geo Restriction ───────────────────────────────────────────────────────
  restrictions {
    geo_restriction {
      restriction_type = length(var.geo_restriction_locations) > 0 ? "blacklist" : "none"
      locations        = var.geo_restriction_locations
    }
  }

  # ── TLS Certificate ───────────────────────────────────────────────────────
  viewer_certificate {
    acm_certificate_arn            = var.certificate_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
    cloudfront_default_certificate = false
  }

  # ── Custom Error Pages ────────────────────────────────────────────────────
  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 503
    response_code         = 503
    response_page_path    = "/503.html"
    error_caching_min_ttl = 10
  }

  # ── Access Logs ───────────────────────────────────────────────────────────
  dynamic "logging_config" {
    for_each = var.s3_logs_bucket != null ? [1] : []
    content {
      include_cookies = false
      bucket          = var.s3_logs_bucket
      prefix          = "cloudfront/"
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-cdn" })
}

###############################################################################
# Security Response Headers Policy
###############################################################################

resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name    = "${var.name_prefix}-security-headers"
  comment = "HSTS, anti-clickjack, MIME-sniff, CSP, Referrer-Policy"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    content_type_options {
      override = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=(), payment=()"
      override = true
    }
  }
}
