output "kms_key_arns" {
  description = "Map of KMS key ARNs keyed by service name"
  value       = { for k, v in aws_kms_key.main : k => v.arn }
}
output "kms_key_ids" {
  value = { for k, v in aws_kms_key.main : k => v.key_id }
}
