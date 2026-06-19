###############################################################################
# Blue-Green — CodeDeploy application and deployment group
###############################################################################

resource "aws_iam_role" "codedeploy" {
  name = "${var.name_prefix}-codedeploy-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

resource "aws_codedeploy_app" "main" {
  name             = "${var.name_prefix}-app"
  compute_platform = "ECS"
  tags             = var.tags
}

resource "aws_codedeploy_deployment_group" "main" {
  app_name               = aws_codedeploy_app.main.name
  deployment_group_name  = "${var.name_prefix}-dg"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = local.deployment_config

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout    = "CONTINUE_DEPLOYMENT"
      wait_time_in_minutes = 0
    }

    green_fleet_provisioning_option {
      action = "DISCOVER_EXISTING"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = var.terminate_blue_after_minutes
    }
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = var.alb_listener_arns
      }

      target_group {
        name = var.blue_target_group_name
      }

      target_group {
        name = var.green_target_group_name
      }
    }
  }

  dynamic "auto_rollback_configuration" {
    for_each = length(var.auto_rollback_alarms) > 0 ? [1] : []
    content {
      enabled = true
      events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
    }
  }

  dynamic "alarm_configuration" {
    for_each = length(var.auto_rollback_alarms) > 0 ? [1] : []
    content {
      alarms  = var.auto_rollback_alarms
      enabled = true
    }
  }

  tags = var.tags
}

locals {
  deployment_config = var.traffic_routing_type == "AllAtOnce" ? "CodeDeployDefault.ECSAllAtOnce" : "CodeDeployDefault.ECSLinear${var.traffic_routing_percentage}PercentEvery${var.traffic_routing_interval}Minutes"
}

# ── SNS Notifications ─────────────────────────────────────────────────────────
resource "aws_sns_topic" "deployments" {
  name = "${var.name_prefix}-deployments"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.sns_notification_email != null ? 1 : 0
  topic_arn = aws_sns_topic.deployments.arn
  protocol  = "email"
  endpoint  = var.sns_notification_email
}

resource "aws_codedeploy_deployment_group" "notification" {
  depends_on            = [aws_codedeploy_deployment_group.main]
  app_name              = aws_codedeploy_app.main.name
  deployment_group_name = aws_codedeploy_deployment_group.main.deployment_group_name
  service_role_arn      = aws_iam_role.codedeploy.arn

  trigger_configuration {
    trigger_events     = ["DeploymentSuccess", "DeploymentFailure", "DeploymentRollback"]
    trigger_name       = "${var.name_prefix}-trigger"
    trigger_target_arn = aws_sns_topic.deployments.arn
  }

  lifecycle {
    ignore_changes = [deployment_style, blue_green_deployment_config, load_balancer_info]
  }
}
