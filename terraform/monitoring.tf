resource "aws_cloudwatch_log_group" "openclaw" {
  name              = "/${var.project_name}/openclaw"
  retention_in_days = var.log_retention_days

  tags = { Name = "${var.project_name}-openclaw-logs" }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = var.instances

  alarm_name          = "${var.project_name}-${each.key}-cpu-high"
  alarm_description   = "CPU utilization above 80% for ${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    InstanceId = aws_instance.openclaw[each.key].id
  }

  tags = { Bot = each.key }
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  for_each = var.instances

  alarm_name          = "${var.project_name}-${each.key}-status-check"
  alarm_description   = "Status check failed for ${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0

  dimensions = {
    InstanceId = aws_instance.openclaw[each.key].id
  }

  tags = { Bot = each.key }
}
