output "codedeploy_app_name" {
  value = aws_codedeploy_app.main.name
}
output "deployment_group_name" {
  value = aws_codedeploy_deployment_group.main.deployment_group_name
}
output "sns_topic_arn" {
  value = aws_sns_topic.deployments.arn
}
