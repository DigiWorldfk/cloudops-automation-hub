variable "name_prefix" { type = string }
variable "environment" { type = string }

variable "alb_dns_name" {
  description = "DNS name of the external ALB — used as CloudFront custom origin"
  type        = string
}
variable "certificate_arn" {
  description = "ACM certificate ARN in us-east-1 (required for CloudFront)"
  type        = string
}
variable "domain_name" {
  description = "Primary domain name (e.g. example.com)"
  type        = string
}
variable "aliases" {
  description = "Additional CNAMEs served by this distribution (e.g. www.example.com)"
  type        = list(string)
  default     = []
}
variable "price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}
variable "geo_restriction_locations" {
  description = "ISO 3166-1-alpha-2 country codes to block (empty = no restriction)"
  type        = list(string)
  default     = []
}
variable "waf_web_acl_arn" {
  description = "ARN of the CloudFront-scoped WAF Web ACL (must be in us-east-1)"
  type        = string
  default     = null
}
variable "origin_secret" {
  description = "Shared secret injected as X-CloudFront-Secret header on every origin request. Must match the value configured on the ALB listener rule. Retrieve from SSM \u2014 never use a predictable string."
  type        = string
  sensitive   = true
}
variable "s3_logs_bucket" {
  description = "S3 bucket domain name for CloudFront access logs"
  type        = string
  default     = null
}
variable "default_ttl" {
  type    = number
  default = 3600
}
variable "max_ttl" {
  type    = number
  default = 86400
}
variable "tags" {
  type    = map(string)
  default = {}
}
