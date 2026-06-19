###############################################################################
# Database — Aurora PostgreSQL 15 cluster
###############################################################################

variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "isolated_subnet_ids" { type = list(string) }
variable "allowed_security_group_id" {
  description = "Security group allowed to connect on port 5432 (EKS nodes SG)"
  type        = string
}
variable "engine_version" {
  type    = string
  default = "15.4"
}
variable "instance_class" {
  type    = string
  default = "db.t4g.medium"
}
variable "instance_count" {
  description = "Number of Aurora instances (1 = writer only, 2+ = writer + readers)"
  type        = number
  default     = 1
}
variable "database_name" {
  type    = string
  default = "appdb"
}
variable "master_username" {
  type    = string
  default = "dbadmin"
}
variable "master_password" {
  type      = string
  sensitive = true
}
variable "backup_retention_days" {
  type    = number
  default = 7
}
variable "deletion_protection" {
  type    = bool
  default = false
}
variable "enable_performance_insights" {
  type    = bool
  default = false
}
variable "kms_key_arn" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}
