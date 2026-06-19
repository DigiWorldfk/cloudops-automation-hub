variable "aws_region" {
  type    = string
  default = "eu-west-1"
}
variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}
variable "availability_zones" {
  type    = list(string)
  default = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}
variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
}
variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.10.0/21", "10.20.18.0/21", "10.20.26.0/21"]
}
variable "isolated_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.40.0/28", "10.20.40.16/28", "10.20.40.32/28"]
}
variable "kubernetes_version" {
  type    = string
  default = "1.30"
}
variable "node_instance_types" {
  type    = list(string)
  default = ["m5.xlarge"]
}
variable "node_desired_size" { type = number; default = 3 }
variable "node_min_size" { type = number; default = 3 }
variable "node_max_size" { type = number; default = 10 }

variable "domain_name" {
  description = "Primary domain (e.g. example.com) — set in tfvars"
  type        = string
}
variable "mx_records" {
  type    = list(string)
  default = []
}
variable "blocked_countries" {
  type    = list(string)
  default = []
}
variable "github_org" {
  type = string
}
variable "github_repo" {
  type    = string
  default = "aws-eks-enterprise-platform"
}
variable "db_instance_class" {
  type    = string
  default = "db.r6g.large"
}
variable "db_master_username" {
  type    = string
  default = "dbadmin"
}
variable "db_master_password" {
  type      = string
  sensitive = true
}
variable "notification_email" {
  type    = string
  default = null
}
variable "ssm_secrets" {
  description = "Secrets to store in SSM Parameter Store. Sensitive — pass via CI TF_VAR_ssm_secrets."
  type = map(object({
    value       = string
    description = string
  }))
  default   = {}
  sensitive = true
}

# ── VPC Peering ───────────────────────────────────────────────────────────────
variable "enable_vpc_peering" { type = bool; default = false }
variable "peer_vpc_id" { type = string; default = null }
variable "peer_vpc_cidr" { type = string; default = null }

# ── Transit Gateway ───────────────────────────────────────────────────────────
variable "enable_transit_gateway" { type = bool; default = false }
variable "tgw_destination_cidrs" { type = list(string); default = [] }

# ── VPN ───────────────────────────────────────────────────────────────────────
variable "enable_vpn" { type = bool; default = false }
variable "customer_gateway_ip" { type = string; default = null }
variable "vpn_destination_cidrs" { type = list(string); default = [] }

# ── Internal NLB ─────────────────────────────────────────────────────────────
variable "db_target_ips" {
  description = "IP addresses of database nodes (Aurora writer + readers, or self-hosted replicas) for the internal NLB target group."
  type        = list(string)
  default     = []
}

variable "db_engine" {
  description = "Database engine — used to derive the default port (postgres=5432, mysql=3306)."
  type        = string
  default     = "postgres"

  validation {
    condition     = contains(["postgres", "mysql"], var.db_engine)
    error_message = "db_engine must be 'postgres' or 'mysql'."
  }
}

# ── Security hardening ─────────────────────────────────────────────────────────────
variable "cloudfront_origin_secret" {
  description = "Shared secret injected by CloudFront as X-CloudFront-Secret on every origin request. ALB blocks requests without it. Generate with: openssl rand -hex 32. Set via CI TF_VAR_cloudfront_origin_secret or tfvars (never commit to git)."
  type        = string
  sensitive   = true
  default     = null
}

variable "security_alert_email" {
  description = "Email address to receive GuardDuty HIGH-severity finding alerts via SNS. Confirm the SNS subscription after first apply."
  type        = string
  default     = null
}
