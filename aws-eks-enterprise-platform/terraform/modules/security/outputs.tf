output "kms_key_arns" {
  description = "Map of KMS key ARNs keyed by service name"
  value       = { for k, v in aws_kms_key.main : k => v.arn }
}
output "kms_key_ids" {
  value = { for k, v in aws_kms_key.main : k => v.key_id }
}
output "guardduty_detector_id" {
  value = aws_guardduty_detector.main.id
}
output "irsa_role_arns" {
  description = "Map of IRSA role ARNs keyed by service account name"
  value       = { for k, v in aws_iam_role.irsa : k => v.arn }
}
