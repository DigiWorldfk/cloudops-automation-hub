output "hosted_zone_id" {
  value = aws_route53_zone.main.zone_id
}
output "name_servers" {
  description = "Route53 name servers — configure these at your domain registrar"
  value       = aws_route53_zone.main.name_servers
}
output "cloudfront_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 for CloudFront"
  value       = aws_acm_certificate_validation.cloudfront.certificate_arn
}
output "regional_certificate_arn" {
  description = "ACM certificate ARN in deployment region for ALB"
  value       = aws_acm_certificate_validation.regional.certificate_arn
}
