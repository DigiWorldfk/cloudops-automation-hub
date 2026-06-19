output "github_actions_role_arn" {
  description = "IAM Role ARN — set as AWS_ROLE_ARN in GitHub Actions workflow"
  value       = aws_iam_role.github_actions.arn
}
output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github_actions.arn
}
