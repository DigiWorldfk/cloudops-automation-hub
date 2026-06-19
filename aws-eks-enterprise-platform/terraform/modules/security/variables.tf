variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "oidc_provider_arn" { type = string; default = null }
variable "oidc_provider_url" { type = string; default = null }
variable "cloudtrail_s3_bucket" {
  description = "S3 bucket name for CloudTrail logs"
  type        = string
}
variable "security_alert_email" {
  description = "Email address to receive GuardDuty high-severity finding alerts via SNS"
  type        = string
  default     = null
}
variable "irsa_service_accounts" {
  description = "Map of IRSA roles to create. Key = role short name."
  type = map(object({
    namespace       = string
    service_account = string
    policy_json     = string
  }))
  default = {}
}
variable "tags" {
  type    = map(string)
  default = {}
}
