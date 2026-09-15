variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "kms_key_arns" {
  description = "KMS key ARNs keyed by service name (from module.kms) — used for CloudTrail, GuardDuty SNS, and findings export encryption"
  type        = map(string)
}
variable "cloudtrail_s3_bucket" {
  description = "S3 bucket name for CloudTrail logs"
  type        = string
}
variable "security_alert_email" {
  description = "Email address to receive GuardDuty high-severity finding alerts via SNS"
  type        = string
  default     = null
}
variable "tags" {
  type    = map(string)
  default = {}
}
