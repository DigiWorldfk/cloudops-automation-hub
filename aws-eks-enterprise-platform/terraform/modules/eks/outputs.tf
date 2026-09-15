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
output "oidc_issuer_url" {
  description = "EKS OIDC issuer URL; consumed by the dedicated IRSA module"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
