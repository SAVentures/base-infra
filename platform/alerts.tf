# Single shared alerting destination. Per-product topics buy nothing — the
# alarms already name the product, and one subscription is one confirmation
# click instead of N.
resource "aws_sns_topic" "alerts" {
  name = "platform-alerts"

  tags = {
    Name = "Platform alerts"
  }
}

# NOTE: AWS creates email subscriptions in "pending confirmation" and sends a
# link that must be clicked. terraform apply reports success while the
# subscription is inert. See Step 5.
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "hello@shubhanshu.dev"
}
