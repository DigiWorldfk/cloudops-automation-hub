###############################################################################
# ECR — Elastic Container Registry repositories
###############################################################################

variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "repositories" {
  description = "List of ECR repository names to create (e.g. ['frontend', 'backend'])"
  type        = list(string)
  default     = ["frontend", "backend"]
}
variable "image_tag_mutability" {
  type    = string
  default = "IMMUTABLE"
}
variable "scan_on_push" {
  type    = bool
  default = true
}
variable "kms_key_arn" {
  description = "KMS key ARN for ECR encryption"
  type        = string
}
variable "node_role_arn" {
  description = "EKS node IAM role ARN — gets pull access"
  type        = string
}
variable "ci_role_arn" {
  description = "CI/CD IAM role ARN — gets push + pull access"
  type        = string
  default     = null
}
variable "tags" {
  type    = map(string)
  default = {}
}
