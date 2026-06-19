variable "aws_region" { type = string; default = "eu-west-1" }
variable "vpc_cidr" { type = string; default = "10.0.0.0/16" }
variable "availability_zones" { type = list(string); default = ["eu-west-1a", "eu-west-1b", "eu-west-1c"] }
variable "public_subnet_cidrs" { type = list(string); default = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"] }
variable "private_subnet_cidrs" { type = list(string); default = ["10.0.10.0/21", "10.0.18.0/21", "10.0.26.0/21"] }
variable "isolated_subnet_cidrs" { type = list(string); default = ["10.0.40.0/28", "10.0.40.16/28", "10.0.40.32/28"] }
variable "kubernetes_version" { type = string; default = "1.30" }
variable "domain_name" { type = string }
variable "github_org" { type = string }
variable "github_repo" { type = string; default = "aws-eks-enterprise-platform" }
variable "db_master_username" { type = string; default = "dbadmin" }
variable "db_master_password" { type = string; sensitive = true }
variable "ssm_secrets" {
  type = map(object({ value = string; description = string }))
  default   = {}
  sensitive = true
}

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
