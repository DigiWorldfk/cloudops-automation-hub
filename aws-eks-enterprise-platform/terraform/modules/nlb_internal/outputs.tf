output "nlb_arn" {
  description = "ARN of the internal Network Load Balancer"
  value       = aws_lb.internal_db.arn
}

output "nlb_dns_name" {
  description = "DNS name of the internal NLB — use this as DB host in app config"
  value       = aws_lb.internal_db.dns_name
}

output "nlb_zone_id" {
  description = "Canonical hosted zone ID of the NLB (for Route53 ALIAS records)"
  value       = aws_lb.internal_db.zone_id
}

output "target_group_arn" {
  description = "ARN of the TCP target group (register additional DB IPs here)"
  value       = aws_lb_target_group.db.arn
}

output "target_group_name" {
  description = "Name of the TCP target group"
  value       = aws_lb_target_group.db.name
}

output "nlb_security_group_id" {
  description = "Security group ID on the NLB — allow ingress from EKS nodes only"
  value       = aws_security_group.nlb.id
}

output "db_security_group_id" {
  description = "Security group ID on DB nodes — allow ingress from NLB only"
  value       = aws_security_group.db_nodes.id
}

output "listener_arn" {
  description = "ARN of the TCP listener on db_port"
  value       = aws_lb_listener.db.arn
}

output "effective_db_port" {
  description = "Resolved DB port actually used (after engine-default fallback)"
  value       = local.effective_port
}
