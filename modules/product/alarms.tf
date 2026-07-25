# Products only. A prototype must never page anyone — that is the point of the
# tier. Both alarms hang off the target group this module owns, so they answer
# "is this product's API broken" without reaching into the product's stack.

resource "aws_cloudwatch_metric_alarm" "no_healthy_hosts" {
  count = var.tier == "product" ? 1 : 0

  alarm_name          = "${var.product}-no-healthy-hosts"
  alarm_description   = "${var.product} has no healthy targets — the API is down."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = 60
  evaluation_periods  = 2

  # breaching, not notBreaching: CloudWatch stops emitting HealthyHostCount
  # entirely once the target group has zero registered targets — that is
  # every task down, the exact outage this alarm exists to catch. Missing
  # data here means "nothing is registered," not "nothing happened." This is
  # the opposite of target_5xx below, whose metric is genuinely absent during
  # a quiet period.
  treat_missing_data = "breaching"

  alarm_actions = [var.alerts_topic_arn]
  ok_actions    = [var.alerts_topic_arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.api.arn_suffix
    LoadBalancer = var.platform_alb_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  count = var.tier == "product" ? 1 : 0

  alarm_name          = "${var.product}-target-5xx"
  alarm_description   = "${var.product} is returning 5xx from the application."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 10
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.alerts_topic_arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.api.arn_suffix
    LoadBalancer = var.platform_alb_arn_suffix
  }
}
