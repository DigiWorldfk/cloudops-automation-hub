###############################################################################
# AWS EKS Enterprise Platform — prod environment
###############################################################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
  default_tags { tags = local.tags }
}

# us-east-1 provider — required for CloudFront ACM certificate + WAF CLOUDFRONT scope
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags { tags = local.tags }
}

provider "tls" {}

###############################################################################
# Locals
###############################################################################

locals {
  project     = "eks-enterprise"
  env         = "prod"
  name_prefix = "${local.project}-${local.env}"

  tags = {
    environment = local.env
    project     = local.project
    managed_by  = "terraform"
  }
}

###############################################################################
# S3 Buckets (remote state is in bootstrap; these are app/logs/velero)
###############################################################################

module "s3" {
  source      = "../../modules/s3"
  name_prefix = local.name_prefix
  environment = local.env
  kms_key_arn = module.security.kms_key_arns["s3"]
  force_destroy = false
  log_retention_days = 365
  tags        = local.tags
}

###############################################################################
# Security — KMS, GuardDuty, Security Hub, CloudTrail, IRSA roles
###############################################################################

module "security" {
  source               = "../../modules/security"
  name_prefix          = local.name_prefix
  environment          = local.env
  cloudtrail_s3_bucket = module.s3.logs_bucket_id
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  security_alert_email = var.security_alert_email  # GuardDuty high-severity SNS alerts
  irsa_service_accounts = {
    backend = {
      namespace       = "backend"
      service_account = "backend-sa"
      policy_json = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect   = "Allow"
          Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
          Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${local.name_prefix}/*"
        }]
      })
    }
  }
  tags = local.tags

  depends_on = [module.s3, module.eks]
}

###############################################################################
# VPC
###############################################################################

module "vpc" {
  source      = "../../modules/vpc"
  name_prefix = local.name_prefix
  environment = local.env

  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  isolated_subnet_cidrs = var.isolated_subnet_cidrs
  single_nat_gateway    = false # one NAT GW per AZ in prod

  enable_transit_gateway = var.enable_transit_gateway
  tgw_destination_cidrs  = var.tgw_destination_cidrs
  enable_vpc_peering     = var.enable_vpc_peering
  peer_vpc_id            = var.peer_vpc_id
  peer_vpc_cidr          = var.peer_vpc_cidr
  enable_vpn             = var.enable_vpn
  customer_gateway_ip    = var.customer_gateway_ip
  vpn_destination_cidrs  = var.vpn_destination_cidrs

  tags = local.tags
}

###############################################################################
# EKS
###############################################################################

module "eks" {
  source      = "../../modules/eks"
  name_prefix = local.name_prefix
  environment = local.env

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  vpc_cidr           = var.vpc_cidr          # scopes cluster SG egress to VPC-internal traffic
  kms_key_arn        = module.security.kms_key_arns["eks"]  # encrypts k8s Secrets at rest

  kubernetes_version      = var.kubernetes_version
  node_instance_types     = var.node_instance_types
  node_capacity_type      = "ON_DEMAND"
  node_desired_size       = var.node_desired_size
  node_min_size           = var.node_min_size
  node_max_size           = var.node_max_size
  node_disk_size          = 100
  endpoint_private_access = true
  endpoint_public_access  = false # private-only in prod
  enable_irsa             = true
  log_retention_days      = 90

  tags = local.tags
}

###############################################################################
# Domain + ACM Certificates
###############################################################################

module "domain" {
  source    = "../../modules/domain"
  providers = { aws.us_east_1 = aws.us_east_1 }

  name_prefix               = local.name_prefix
  environment               = local.env
  domain_name               = var.domain_name
  cloudfront_domain_name    = module.cdn.domain_name
  cloudfront_hosted_zone_id = module.cdn.hosted_zone_id
  alb_dns_name              = module.alb.alb_external_dns_name
  alb_hosted_zone_id        = module.alb.alb_external_zone_id
  mx_records                = var.mx_records
  subject_alternative_names = ["*.${var.domain_name}"]
  tags                      = local.tags

  depends_on = [module.cdn, module.alb]
}

###############################################################################
# ALB
###############################################################################

module "alb" {
  source      = "../../modules/alb"
  name_prefix = local.name_prefix
  environment = local.env

  vpc_id                   = module.vpc.vpc_id
  public_subnet_ids        = module.vpc.public_subnet_ids
  private_subnet_ids       = module.vpc.private_subnet_ids
  certificate_arn          = module.domain.regional_certificate_arn
  deletion_protection      = true
  access_logs_bucket       = module.s3.logs_bucket_id
  cloudfront_origin_secret = var.cloudfront_origin_secret  # enforced via ALB listener rule

  tags = local.tags
}

###############################################################################
# WAF (REGIONAL — ALB)
###############################################################################

module "waf_regional" {
  source      = "../../modules/waf"
  name_prefix = "${local.name_prefix}-regional"
  environment = local.env

  scope              = "REGIONAL"
  alb_arn            = module.alb.alb_external_arn
  waf_mode           = "BLOCK"
  rate_limit         = 2000  # per real client IP via X-Forwarded-For (FORWARDED_IP aggregation)
  blocked_countries  = var.blocked_countries
  enable_bot_control = true  # Bot Control: L7 DDoS + credential-stuffing detection
  s3_logs_bucket_arn = module.s3.bucket_arns["logs"]

  tags = local.tags
}

###############################################################################
# CDN — CloudFront
###############################################################################

module "cdn" {
  source      = "../../modules/cdn"
  name_prefix = local.name_prefix
  environment = local.env

  alb_dns_name    = module.alb.alb_external_dns_name
  certificate_arn = module.domain.cloudfront_certificate_arn
  domain_name     = var.domain_name
  aliases         = ["www.${var.domain_name}"]
  price_class     = "PriceClass_100"
  waf_web_acl_arn = module.waf_cloudfront.web_acl_arn
  s3_logs_bucket  = module.s3.logs_bucket_domain_name
  origin_secret   = var.cloudfront_origin_secret  # injected as X-CloudFront-Secret on origin requests

  tags = local.tags
}

###############################################################################
# WAF (CLOUDFRONT — us-east-1)
###############################################################################

module "waf_cloudfront" {
  source    = "../../modules/waf"
  providers = { aws = aws.us_east_1 }

  name_prefix        = "${local.name_prefix}-cf"
  environment        = local.env

  scope              = "CLOUDFRONT"
  waf_mode           = "BLOCK"
  rate_limit         = 2000  # per real client IP via FORWARDED_IP aggregation
  enable_bot_control = true  # Bot Control: L7 DDoS + credential-stuffing detection

  tags = local.tags
}

###############################################################################
# ECR
###############################################################################

module "ecr" {
  source      = "../../modules/ecr"
  name_prefix = local.name_prefix
  environment = local.env

  repositories         = ["frontend", "backend"]
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  kms_key_arn          = module.security.kms_key_arns["eks"]
  node_role_arn        = module.eks.node_role_arn
  ci_role_arn          = module.cicd.github_actions_role_arn

  tags = local.tags
}

###############################################################################
# CICD — GitHub Actions OIDC
###############################################################################

module "cicd" {
  source      = "../../modules/cicd"
  name_prefix = local.name_prefix
  environment = local.env

  github_org          = var.github_org
  github_repo         = var.github_repo
  ecr_repository_arns = values(module.ecr.repository_arns)
  eks_cluster_name    = module.eks.cluster_name
  ssm_parameter_prefix = "/${local.name_prefix}"

  tags = local.tags
}

###############################################################################
# Database — Aurora PostgreSQL
###############################################################################

module "database" {
  source      = "../../modules/database"
  name_prefix = local.name_prefix
  environment = local.env

  vpc_id                    = module.vpc.vpc_id
  isolated_subnet_ids       = module.vpc.isolated_subnet_ids
  allowed_security_group_id = module.eks.cluster_security_group_id
  instance_class            = var.db_instance_class
  instance_count            = 2 # writer + reader in prod
  master_username           = var.db_master_username
  master_password           = var.db_master_password
  backup_retention_days     = 35
  deletion_protection       = true
  enable_performance_insights = true
  kms_key_arn               = module.security.kms_key_arns["rds"]

  tags = local.tags
}

###############################################################################
# SSM Secrets
###############################################################################

module "ssm_secrets" {
  source      = "../../modules/ssm_secrets"
  name_prefix = local.name_prefix
  environment = local.env

  kms_key_arn = module.security.kms_key_arns["ssm"]
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  workload_role_arns  = values(module.security.irsa_role_arns)
  enable_write_policy = true

  secrets = var.ssm_secrets

  tags = local.tags
}

###############################################################################
# Blue-Green Deployment
###############################################################################

module "blue_green" {
  source      = "../../modules/blue_green"
  name_prefix = local.name_prefix
  environment = local.env

  blue_target_group_name  = "${local.name_prefix}-tg-blue"
  green_target_group_name = "${local.name_prefix}-tg-green"
  alb_listener_arns       = [module.alb.https_listener_arn]

  traffic_routing_type       = "TimeBasedLinear"
  traffic_routing_interval   = 5
  traffic_routing_percentage = 25
  terminate_blue_after_minutes = 5
  sns_notification_email     = var.notification_email

  auto_rollback_alarms = [
    aws_cloudwatch_metric_alarm.error_rate.alarm_name,
    aws_cloudwatch_metric_alarm.latency.alarm_name,
  ]

  tags = local.tags

  depends_on = [module.alb]
}

# ── Rollback alarms ───────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "error_rate" {
  alarm_name          = "${local.name_prefix}-5xx-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Triggers rollback if backend 5XX > 10 per minute"

  dimensions = {
    LoadBalancer = module.alb.alb_external_arn
  }
}

resource "aws_cloudwatch_metric_alarm" "latency" {
  alarm_name          = "${local.name_prefix}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "p99"
  threshold           = 2.0
  alarm_description   = "Triggers rollback if p99 latency > 2s"

  dimensions = {
    LoadBalancer = module.alb.alb_external_arn
  }
}

###############################################################################
# Internal NLB — EKS → Database tier
###############################################################################

module "nlb_internal" {
  source      = "../../modules/nlb_internal"
  name_prefix = local.name_prefix
  environment = local.env

  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.cluster_security_group_id
  eks_node_subnet_cidrs      = var.private_subnet_cidrs

  db_engine     = var.db_engine
  db_target_ips = var.db_target_ips

  deletion_protection              = true    # prod — protect against accidental destroy
  enable_cross_zone_load_balancing = true
  access_logs_bucket               = module.s3.logs_bucket_id
  health_check_interval            = 10
  health_check_healthy_threshold   = 3
  health_check_unhealthy_threshold = 2

  tags = local.tags

  depends_on = [module.vpc, module.eks, module.s3]
}
