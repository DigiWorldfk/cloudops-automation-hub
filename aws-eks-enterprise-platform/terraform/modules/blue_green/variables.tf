###############################################################################
# Blue-Green — CodeDeploy blue/green deployments for EKS workloads
###############################################################################

variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "blue_target_group_name" { type = string }
variable "green_target_group_name" { type = string }
variable "alb_listener_arns" {
  description = "ALB listener ARNs CodeDeploy will shift traffic on"
  type        = list(string)
}
variable "auto_rollback_alarms" {
  description = "CloudWatch alarm names that trigger automatic rollback"
  type        = list(string)
  default     = []
}
variable "traffic_routing_type" {
  description = "AllAtOnce | TimeBasedLinear | TimeBasedCanary"
  type        = string
  default     = "AllAtOnce"
}
variable "traffic_routing_interval" {
  description = "Interval in minutes between traffic shifts (TimeBasedLinear/Canary)"
  type        = number
  default     = 5
}
variable "traffic_routing_percentage" {
  description = "Percentage of traffic to shift per interval"
  type        = number
  default     = 25
}
variable "terminate_blue_after_minutes" {
  type    = number
  default = 5
}
variable "sns_notification_email" {
  description = "Email address for deployment notifications"
  type        = string
  default     = null
}
variable "tags" {
  type    = map(string)
  default = {}
}
