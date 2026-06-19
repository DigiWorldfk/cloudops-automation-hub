output "alb_external_arn" {
  value = aws_lb.external.arn
}
output "alb_external_dns_name" {
  value = aws_lb.external.dns_name
}
output "alb_external_zone_id" {
  value = aws_lb.external.zone_id
}
output "alb_internal_dns_name" {
  value = var.enable_internal_alb ? aws_lb.internal[0].dns_name : null
}
output "alb_external_sg_id" {
  value = aws_security_group.alb_external.id
}
output "https_listener_arn" {
  value = aws_lb_listener.https.arn
}
output "blue_target_group_arn" {
  value = aws_lb_target_group.blue.arn
}
output "green_target_group_arn" {
  value = aws_lb_target_group.green.arn
}
