output "cluster_endpoint" {
  description = "Writer endpoint"
  value       = aws_rds_cluster.main.endpoint
}
output "cluster_reader_endpoint" {
  description = "Load-balanced reader endpoint"
  value       = aws_rds_cluster.main.reader_endpoint
}
output "cluster_identifier" {
  value = aws_rds_cluster.main.cluster_identifier
}
output "cluster_port" {
  value = aws_rds_cluster.main.port
}
output "database_name" {
  value = aws_rds_cluster.main.database_name
}
output "db_security_group_id" {
  value = aws_security_group.db.id
}
output "credentials_secret_arn" {
  description = "Secrets Manager ARN storing DB credentials JSON"
  value       = aws_secretsmanager_secret.db_credentials.arn
}
