output "cluster_name" {
  description = "EKS cluster name — use with: aws eks update-kubeconfig --name <cluster_name>"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN used by IRSA"
  value       = module.irsa_oidc.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "EKS OIDC issuer host (without https://)"
  value       = module.irsa_oidc.oidc_provider_url
}

output "irsa_role_arns" {
  description = "IRSA role ARNs keyed by service-account role name — annotate the matching Kubernetes ServiceAccount with eks.amazonaws.com/role-arn"
  value       = module.irsa_oidc.role_arns
}

output "eso_role_arn" {
  description = "External Secrets Operator IRSA role ARN — annotate external-secrets-sa with this value"
  value       = module.ssm_secrets.eso_role_arn
}
