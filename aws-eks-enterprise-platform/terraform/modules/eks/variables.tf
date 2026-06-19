variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "vpc_cidr" {
  description = "VPC CIDR block — used to scope cluster SG egress rules to VPC-internal traffic only"
  type        = string
  default     = "10.0.0.0/8"
}
variable "kms_key_arn" {
  description = "KMS key ARN for encrypting Kubernetes Secrets at rest in etcd"
  type        = string
  default     = null
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}
variable "node_instance_types" {
  type    = list(string)
  default = ["t3.large"]
}
variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT"
  type        = string
  default     = "ON_DEMAND"
}
variable "node_desired_size" { type = number; default = 2 }
variable "node_min_size" { type = number; default = 1 }
variable "node_max_size" { type = number; default = 10 }
variable "node_disk_size" { type = number; default = 50 }

variable "endpoint_private_access" {
  type    = bool
  default = true
}
variable "endpoint_public_access" {
  type    = bool
  default = true
}
variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Empty list = no public access (recommended for prod). Only set when endpoint_public_access = true."
  type        = list(string)
  default     = []  # was 0.0.0.0/0 — changed to deny-by-default; must be explicitly set per environment
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts (OIDC provider)"
  type        = bool
  default     = true
}
variable "enable_cluster_autoscaler" {
  type    = bool
  default = true
}
variable "enable_external_secrets" {
  description = "Install External Secrets Operator via Helm"
  type        = bool
  default     = true
}
variable "cluster_log_types" {
  type    = list(string)
  default = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}
variable "log_retention_days" {
  type    = number
  default = 30
}
variable "tags" {
  type    = map(string)
  default = {}
}
