output "cluster_name" {
  value = aws_eks_cluster.main.name
}
output "cluster_arn" {
  value = aws_eks_cluster.main.arn
}
output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}
output "cluster_certificate_authority" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}
output "cluster_version" {
  value = aws_eks_cluster.main.version
}
output "cluster_security_group_id" {
  value = aws_security_group.cluster.id
}
output "node_role_arn" {
  value = aws_iam_role.node.arn
}
output "node_role_name" {
  value = aws_iam_role.node.name
}
output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = var.enable_irsa ? aws_iam_openid_connect_provider.eks[0].arn : null
}
output "oidc_provider_url" {
  description = "OIDC issuer URL (without https://)"
  value       = var.enable_irsa ? trimprefix(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://") : null
}
