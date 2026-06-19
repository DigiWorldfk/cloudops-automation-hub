variable "name_prefix" { type = string }
variable "environment" { type = string }

variable "scope" {
  description = "CLOUDFRONT (us-east-1) or REGIONAL (same region as ALB)"
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["CLOUDFRONT", "REGIONAL"], var.scope)
    error_message = "scope must be CLOUDFRONT or REGIONAL."
  }
}
variable "alb_arn" {
  description = "ARN of the ALB to associate (REGIONAL scope only)"
  type        = string
  default     = null
}
variable "waf_mode" {
  description = "BLOCK (prod/staging) or COUNT (dev)"
  type        = string
  default     = "BLOCK"
  validation {
    condition     = contains(["BLOCK", "COUNT"], var.waf_mode)
    error_message = "waf_mode must be BLOCK or COUNT."
  }
}
variable "rate_limit" {
  description = "Max requests per 5-minute window per IP before rate-limit rule triggers"
  type        = number
  default     = 2000  # 300 was too low — legitimate mobile clients on 3G/4G hit it; 2000 = ~6.7 req/s per real IP
}
variable "blocked_countries" {
  description = "ISO 3166 country codes to geo-block"
  type        = list(string)
  default     = []
}
variable "s3_logs_bucket_arn" {
  description = "ARN of S3 bucket for WAF logs (Kinesis Firehose delivery)"
  type        = string
  default     = null
}
variable "enable_bot_control" {
  description = "Enable AWS Managed Bot Control rule group. BLOCK mode in prod/staging, COUNT in dev. Detects and mitigates L7 bot floods and credential-stuffing."
  type        = bool
  default     = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
