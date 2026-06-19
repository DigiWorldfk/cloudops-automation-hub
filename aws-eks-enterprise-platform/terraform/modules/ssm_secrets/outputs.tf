output "parameter_arns" {
  description = "Map of secret name → SSM parameter ARN"
  value       = { for k, v in aws_ssm_parameter.main : k => v.arn }
}
output "parameter_names" {
  description = "Map of secret name → SSM parameter full path"
  value       = { for k, v in aws_ssm_parameter.main : k => v.name }
}
output "read_policy_arn" {
  value = aws_iam_policy.ssm_read.arn
}
output "write_policy_arn" {
  value = var.enable_write_policy ? aws_iam_policy.ssm_write[0].arn : null
}
output "eso_role_arn" {
  description = "External Secrets Operator IRSA role ARN"
  value       = var.oidc_provider_arn != null ? aws_iam_role.eso[0].arn : null
}
output "parameter_path_prefix" {
  description = "SSM path prefix for all secrets in this module"
  value       = "/${var.name_prefix}/${var.environment}"
}
