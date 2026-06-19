###############################################################################
# AWS EKS Enterprise Platform — staging environment
###############################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws"; version = "~> 5.50" }
    tls = { source = "hashicorp/tls"; version = "~> 4.0" }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
  default_tags { tags = local.tags }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags { tags = local.tags }
}

provider "tls" {}

locals {
  project     = "eks-enterprise"
  env         = "staging"
  name_prefix = "${local.project}-${local.env}"
  tags = {
    environment = local.env
    project     = local.project
    managed_by  = "terraform"
  }
}

module "s3" {
  source             = "../../modules/s3"
  name_prefix        = local.name_prefix
  environment        = local.env
  kms_key_arn        = module.security.kms_key_arns["s3"]
  force_destroy      = false
  log_retention_days = 90
  tags               = local.tags
}

module "security" {
  source               = "../../modules/security"
  name_prefix          = local.name_prefix
  environment          = local.env
  cloudtrail_s3_bucket = module.s3.logs_bucket_id
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  tags                 = local.tags
  depends_on           = [module.s3, module.eks]
}

module "vpc" {
  source                = "../../modules/vpc"
  name_prefix           = local.name_prefix
  environment           = local.env
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  isolated_subnet_cidrs = var.isolated_subnet_cidrs
  single_nat_gateway    = true
  tags                  = local.tags
}

module "eks" {
  source                  = "../../modules/eks"
  name_prefix             = local.name_prefix
  environment             = local.env
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  kubernetes_version      = var.kubernetes_version
  node_instance_types     = ["t3.large"]
  node_capacity_type      = "ON_DEMAND"
  node_desired_size       = 2
  node_min_size           = 2
  node_max_size           = 6
  node_disk_size          = 50
  endpoint_private_access = true
  endpoint_public_access  = true
  public_access_cidrs     = var.allowed_cidr_blocks
  enable_irsa             = true
  log_retention_days      = 30
  tags                    = local.tags
}

module "domain" {
  source                    = "../../modules/domain"
  providers                 = { aws.us_east_1 = aws.us_east_1 }
  name_prefix               = local.name_prefix
  environment               = local.env
  domain_name               = var.domain_name
  cloudfront_domain_name    = module.cdn.domain_name
  cloudfront_hosted_zone_id = module.cdn.hosted_zone_id
  alb_dns_name              = module.alb.alb_external_dns_name
  alb_hosted_zone_id        = module.alb.alb_external_zone_id
  tags                      = local.tags
  depends_on                = [module.cdn, module.alb]
}

module "alb" {
  source              = "../../modules/alb"
  name_prefix         = local.name_prefix
  environment         = local.env
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  private_subnet_ids  = module.vpc.private_subnet_ids
  certificate_arn     = module.domain.regional_certificate_arn
  deletion_protection = false
  access_logs_bucket  = module.s3.logs_bucket_id
  tags                = local.tags
}

module "waf_regional" {
  source      = "../../modules/waf"
  name_prefix = "${local.name_prefix}-regional"
  environment = local.env
  scope       = "REGIONAL"
  alb_arn     = module.alb.alb_external_arn
  waf_mode    = "BLOCK"
  rate_limit  = 500
  tags        = local.tags
}

module "cdn" {
  source          = "../../modules/cdn"
  name_prefix     = local.name_prefix
  environment     = local.env
  alb_dns_name    = module.alb.alb_external_dns_name
  certificate_arn = module.domain.cloudfront_certificate_arn
  domain_name     = var.domain_name
  price_class     = "PriceClass_100"
  waf_web_acl_arn = module.waf_cloudfront.web_acl_arn
  s3_logs_bucket  = module.s3.logs_bucket_domain_name
  tags            = local.tags
}

module "waf_cloudfront" {
  source      = "../../modules/waf"
  providers   = { aws = aws.us_east_1 }
  name_prefix = "${local.name_prefix}-cf"
  environment = local.env
  scope       = "CLOUDFRONT"
  waf_mode    = "BLOCK"
  rate_limit  = 500
  tags        = local.tags
}

module "ecr" {
  source               = "../../modules/ecr"
  name_prefix          = local.name_prefix
  environment          = local.env
  repositories         = ["frontend", "backend"]
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  kms_key_arn          = module.security.kms_key_arns["eks"]
  node_role_arn        = module.eks.node_role_arn
  ci_role_arn          = module.cicd.github_actions_role_arn
  tags                 = local.tags
}

module "cicd" {
  source               = "../../modules/cicd"
  name_prefix          = local.name_prefix
  environment          = local.env
  github_org           = var.github_org
  github_repo          = var.github_repo
  ecr_repository_arns  = values(module.ecr.repository_arns)
  eks_cluster_name     = module.eks.cluster_name
  ssm_parameter_prefix = "/${local.name_prefix}"
  tags                 = local.tags
}

module "database" {
  source                    = "../../modules/database"
  name_prefix               = local.name_prefix
  environment               = local.env
  vpc_id                    = module.vpc.vpc_id
  isolated_subnet_ids       = module.vpc.isolated_subnet_ids
  allowed_security_group_id = module.eks.cluster_security_group_id
  instance_class            = "db.r6g.large"
  instance_count            = 1
  master_username           = var.db_master_username
  master_password           = var.db_master_password
  backup_retention_days     = 14
  deletion_protection       = false
  kms_key_arn               = module.security.kms_key_arns["rds"]
  tags                      = local.tags
}

module "ssm_secrets" {
  source              = "../../modules/ssm_secrets"
  name_prefix         = local.name_prefix
  environment         = local.env
  kms_key_arn         = module.security.kms_key_arns["ssm"]
  oidc_provider_arn   = module.eks.oidc_provider_arn
  oidc_provider_url   = module.eks.oidc_provider_url
  workload_role_arns  = values(module.security.irsa_role_arns)
  enable_write_policy = true
  secrets             = var.ssm_secrets
  tags                = local.tags
}

module "blue_green" {
  source                     = "../../modules/blue_green"
  name_prefix                = local.name_prefix
  environment                = local.env
  blue_target_group_name     = "${local.name_prefix}-tg-blue"
  green_target_group_name    = "${local.name_prefix}-tg-green"
  alb_listener_arns          = [module.alb.https_listener_arn]
  traffic_routing_type       = "TimeBasedLinear"
  traffic_routing_interval   = 5
  traffic_routing_percentage = 50
  terminate_blue_after_minutes = 5
  sns_notification_email     = var.notification_email
  tags                       = local.tags
  depends_on                 = [module.alb]
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

  deletion_protection              = false   # staging — allow teardown
  enable_cross_zone_load_balancing = true
  health_check_interval            = 10
  health_check_healthy_threshold   = 2
  health_check_unhealthy_threshold = 2

  tags = local.tags

  depends_on = [module.vpc, module.eks]
}
