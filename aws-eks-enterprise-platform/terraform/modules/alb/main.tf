###############################################################################
# ALB — Application Load Balancer (external + optional internal)
###############################################################################

# ── CloudFront origin-facing prefix list (restricts ALB ingress to CF IPs) ───
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# ── Security Group ────────────────────────────────────────────────────────────
resource "aws_security_group" "alb_external" {
  name        = "${var.name_prefix}-alb-external-sg"
  description = "External ALB — allow 80/443 from CloudFront origin-facing IPs only"
  vpc_id      = var.vpc_id

  # HTTP — redirect to HTTPS; accept from CloudFront edge nodes only
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
    description     = "CloudFront origin-facing IPs — HTTP redirect"
  }
  # HTTPS — CloudFront origin requests only; direct access is blocked
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
    description     = "CloudFront origin-facing IPs — HTTPS"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-external-sg" })
}

# ── External ALB ──────────────────────────────────────────────────────────────
resource "aws_lb" "external" {
  name                       = "${var.name_prefix}-alb-ext"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_external.id]
  subnets                    = var.public_subnet_ids
  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.deletion_protection
  # Prevents HTTP request smuggling (Transfer-Encoding + Content-Length conflicts)
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.access_logs_bucket != null ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = "alb-external"
      enabled = true
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-ext" })
}

# ── HTTP → HTTPS Redirect Listener ───────────────────────────────────────────
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.external.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ── HTTPS Listener ────────────────────────────────────────────────────────────
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.external.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  # Default: block — listener rules below override this for valid CloudFront requests
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }
}

# ── Enforce CloudFront origin secret (priority 1 — evaluated first) ───────────
# CloudFront injects X-CloudFront-Secret on every origin request.
# Requests without the correct header are rejected before reaching pods.
resource "aws_lb_listener_rule" "require_cf_secret" {
  count        = var.cloudfront_origin_secret != null ? 1 : 0
  listener_arn = aws_lb_listener.https.arn
  priority     = 1

  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = [var.cloudfront_origin_secret]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

# ── Blue Target Group ─────────────────────────────────────────────────────────
resource "aws_lb_target_group" "blue" {
  name        = "${var.name_prefix}-tg-blue"
  port        = var.blue_target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200-299"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-tg-blue" })

  lifecycle {
    create_before_destroy = true
  }
}

# ── Green Target Group ────────────────────────────────────────────────────────
resource "aws_lb_target_group" "green" {
  name        = "${var.name_prefix}-tg-green"
  port        = var.green_target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    matcher             = "200-299"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-tg-green" })

  lifecycle {
    create_before_destroy = true
  }
}

# ── Internal ALB (optional — service-to-service) ──────────────────────────────
resource "aws_security_group" "alb_internal" {
  count       = var.enable_internal_alb ? 1 : 0
  name        = "${var.name_prefix}-alb-internal-sg"
  description = "Internal ALB — allow 80/443 from within VPC"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-internal-sg" })
}

resource "aws_lb" "internal" {
  count                      = var.enable_internal_alb ? 1 : 0
  name                       = "${var.name_prefix}-alb-int"
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_internal[0].id]
  subnets                    = var.private_subnet_ids
  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.deletion_protection

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-int" })
}

resource "aws_lb_listener" "internal_http" {
  count             = var.enable_internal_alb ? 1 : 0
  load_balancer_arn = aws_lb.internal[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}
