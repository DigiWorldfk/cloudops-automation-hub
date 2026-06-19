variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "domain_name" {
  description = "Apex domain (e.g. example.com)"
  type        = string
}
variable "cloudfront_domain_name" {
  description = "CloudFront distribution domain — used for ALIAS @ record"
  type        = string
}
variable "cloudfront_hosted_zone_id" {
  description = "CloudFront hosted zone ID for ALIAS records"
  type        = string
}
variable "alb_dns_name" {
  description = "ALB DNS name — used for api/app CNAME in non-prod or as fallback"
  type        = string
  default     = null
}
variable "alb_hosted_zone_id" {
  description = "ALB canonical hosted zone ID for ALIAS records"
  type        = string
  default     = null
}
variable "mx_records" {
  description = "MX record values (e.g. ['10 mail.example.com'])"
  type        = list(string)
  default     = []
}
variable "spf_record" {
  description = "SPF TXT record value"
  type        = string
  default     = "v=spf1 include:_spf.google.com ~all"
}
variable "dmarc_policy" {
  description = "DMARC policy: none | quarantine | reject"
  type        = string
  default     = "quarantine"
}
variable "subject_alternative_names" {
  description = "Additional SANs for the ACM certificate (e.g. *.example.com)"
  type        = list(string)
  default     = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
