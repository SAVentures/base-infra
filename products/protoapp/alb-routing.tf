resource "aws_alb_target_group" "ecs_target" {
  name     = "ecs-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.terraform_remote_state.platform.outputs.vpc_id

  health_check {
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    interval            = 30
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

# Protoapp has no X-Product-Id header on its CloudFront, so this rule stays
# header-less. Priority 1000 (low priority) so per-product rules with header
# conditions (e.g. sjocamp at 100) match first. Protoapp catches anything
# without a product-specific header — effectively the default for legacy traffic.
resource "aws_lb_listener_rule" "alb_listener_rule_api_http" {
  listener_arn = data.terraform_remote_state.platform.outputs.alb_listener_http_arn
  priority     = 1000

  action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.ecs_target.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}
