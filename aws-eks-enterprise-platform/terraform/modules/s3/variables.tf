###############################################################################
# S3 — Remote state, app data, logs, Velero backup buckets
###############################################################################

variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "kms_key_arn" {
  description = "KMS key ARN for SSE-KMS encryption"
  type        = string
}
variable "force_destroy" {
  description = "Allow destroying non-empty buckets (dev only)"
  type        = bool
  default     = false
}
variable "log_retention_days" {
  type    = number
  default = 365
}
variable "tags" {
  type    = map(string)
  default = {}
}
