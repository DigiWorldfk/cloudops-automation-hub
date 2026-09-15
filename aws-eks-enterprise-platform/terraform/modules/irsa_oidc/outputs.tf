output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN used by IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "EKS OIDC issuer host without https://"
  value       = var.oidc_issuer_host
}

output "role_arns" {
  description = "IRSA role ARNs keyed by service-account role name"
  value       = { for key, role in aws_iam_role.service_account : key => role.arn }
}
