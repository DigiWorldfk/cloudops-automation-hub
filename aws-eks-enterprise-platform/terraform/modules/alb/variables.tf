variable "name_prefix" {
  type = string
}
variable "environment" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "public_subnet_ids" {
  description = "Subnets for the external ALB"
  type        = list(string)
}
variable "private_subnet_ids" {
  description = "Subnets for the internal ALB"
  type        = list(string)
}
variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener (regional)"
  type        = string
}
variable "enable_internal_alb" {
  description = "Create an internal ALB for service-to-service traffic"
  type        = bool
  default     = true
}
variable "blue_target_port" {
  type    = number
  default = 80
}
variable "green_target_port" {
  type    = number
  default = 80
}
variable "health_check_path" {
  type    = string
  default = "/healthz"
}
variable "idle_timeout" {
  type    = number
  default = 60
}
variable "deletion_protection" {
  type    = bool
  default = false
}
variable "access_logs_bucket" {
  description = "S3 bucket name for ALB access logs"
  type        = string
  default     = null
}
variable "cloudfront_origin_secret" {
  description = "Secret value injected by CloudFront as X-CloudFront-Secret header. ALB rejects requests without it. Retrieve from SSM — do not use a predictable string."
  type        = string
  sensitive   = true
  default     = null
}
variable "tags" {
  type    = map(string)
  default = {}
}
