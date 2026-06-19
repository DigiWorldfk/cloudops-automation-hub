variable "name_prefix" { type = string }
variable "environment" { type = string }

variable "kms_key_arn" {
  description = "KMS key ARN used to encrypt all SecureString parameters"
  type        = string
}
variable "secrets" {
  description = "Map of secret name → { value, description }. Sensitive."
  type = map(object({
    value       = string
    description = string
  }))
  default   = {}
  sensitive = true
}
variable "workload_role_arns" {
  description = "IRSA role ARNs that receive read access to these parameters"
  type        = list(string)
  default     = []
}
variable "enable_write_policy" {
  description = "Create a separate write IAM policy (attach to CI role externally)"
  type        = bool
  default     = false
}
variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN — creates an ESO-dedicated IRSA role"
  type        = string
  default     = null
}
variable "oidc_provider_url" {
  description = "EKS OIDC issuer URL without https://"
  type        = string
  default     = null
}
variable "tags" {
  type    = map(string)
  default = {}
}
