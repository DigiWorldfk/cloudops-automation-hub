###############################################################################
# Internal NLB — Database Tier
# Sits between EKS Application tier and self-hosted / read-replica Database tier
###############################################################################

# ── Identity ──────────────────────────────────────────────────────────────────
variable "name_prefix" {
  description = "Prefix applied to every resource name (e.g. eks-enterprise-prod)"
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev | staging | prod"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

# ── Network ───────────────────────────────────────────────────────────────────
variable "vpc_id" {
  description = "ID of the VPC that contains the EKS nodes and DB instances"
  type        = string
}

variable "private_subnet_ids" {
  description = <<-EOT
    List of exactly three private subnet IDs (one per AZ) where the internal
    NLB will place its network interfaces. Must be in the same VPC.
  EOT
  type        = list(string)
  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least two private subnet IDs are required for high availability."
  }
}

variable "eks_node_security_group_id" {
  description = <<-EOT
    Security group ID attached to EKS worker nodes. Only ingress from this SG
    is allowed to reach the NLB and its DB targets.
  EOT
  type        = string
}

variable "eks_node_subnet_cidrs" {
  description = <<-EOT
    CIDR blocks of the private subnets hosting EKS nodes. Used as a secondary
    ingress constraint on the DB security group (defence-in-depth).
  EOT
  type        = list(string)
  default     = []
}

# ── Database Protocol ─────────────────────────────────────────────────────────
variable "db_engine" {
  description = "Database engine — determines default port. postgres | mysql"
  type        = string
  default     = "postgres"
  validation {
    condition     = contains(["postgres", "mysql"], var.db_engine)
    error_message = "db_engine must be postgres or mysql."
  }
}

variable "db_port" {
  description = <<-EOT
    TCP port the database listens on. Defaults to engine default if set to 0:
    5432 for postgres, 3306 for mysql.
  EOT
  type    = number
  default = 0
}

# ── Target Registration ───────────────────────────────────────────────────────
variable "db_target_ips" {
  description = <<-EOT
    Private IP addresses of the database nodes to register with the target group.
    Typically: Aurora writer + read-replica IPs, or self-hosted Postgres primaries.
    Example: ["10.20.40.10", "10.20.40.26", "10.20.40.42"]
  EOT
  type    = list(string)
  default = []
}

variable "db_target_availability_zones" {
  description = <<-EOT
    AZ for each IP in db_target_ips (parallel list). Required when targets are
    in different AZs to enable cross-zone load balancing correctly.
    Leave empty to use "all" (cross-zone LB enabled by default).
  EOT
  type    = list(string)
  default = []
}

# ── Load Balancing ────────────────────────────────────────────────────────────
variable "enable_cross_zone_load_balancing" {
  description = "Distribute traffic evenly across all targets regardless of AZ"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the NLB (always true in prod)"
  type        = bool
  default     = false
}

variable "deregistration_delay" {
  description = "Seconds to wait before deregistering a draining target (drain timeout)"
  type        = number
  default     = 30
  validation {
    condition     = var.deregistration_delay >= 0 && var.deregistration_delay <= 3600
    error_message = "deregistration_delay must be between 0 and 3600 seconds."
  }
}

# ── Health Check ──────────────────────────────────────────────────────────────
variable "health_check_enabled" {
  type    = bool
  default = true
}

variable "health_check_interval" {
  description = "Seconds between health checks (10 or 30)"
  type        = number
  default     = 10
  validation {
    condition     = contains([10, 30], var.health_check_interval)
    error_message = "NLB health_check_interval must be 10 or 30."
  }
}

variable "health_check_healthy_threshold" {
  description = "Consecutive successes before marking target healthy"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Consecutive failures before removing target from rotation"
  type        = number
  default     = 2
}

# ── Access Logs ───────────────────────────────────────────────────────────────
variable "access_logs_bucket" {
  description = "S3 bucket name for NLB access logs (null = disabled)"
  type        = string
  default     = null
}

variable "access_logs_prefix" {
  description = "S3 key prefix for NLB access logs"
  type        = string
  default     = "nlb-internal"
}

# ── Tags ──────────────────────────────────────────────────────────────────────
variable "tags" {
  description = "Tags applied to every resource created by this module"
  type        = map(string)
  default     = {}
}
