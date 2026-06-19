output "bucket_ids" {
  description = "Map of bucket logical name → S3 bucket ID"
  value       = { for k, v in aws_s3_bucket.main : k => v.id }
}
output "bucket_arns" {
  description = "Map of bucket logical name → S3 bucket ARN"
  value       = { for k, v in aws_s3_bucket.main : k => v.arn }
}
output "state_bucket_id" {
  value = aws_s3_bucket.main["state"].id
}
output "logs_bucket_id" {
  value = aws_s3_bucket.main["logs"].id
}
output "velero_bucket_id" {
  value = aws_s3_bucket.main["velero"].id
}
output "logs_bucket_domain_name" {
  description = "Bucket domain name for CloudFront / ALB access logs"
  value       = aws_s3_bucket.main["logs"].bucket_regional_domain_name
}
