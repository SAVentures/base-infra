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

# Routes /api/* carrying X-Product-Id=protoapp (injected by this product's
# CloudFront) to protoapp's target group. Previously this rule was header-less
# at priority 1000 and acted as a catch-all, silently absorbing any misrouted
# /api/* traffic. The listener's 404 default is now the only fallback.
resource "aws_lb_listener_rule" "alb_listener_rule_api_http" {
  listener_arn = data.terraform_remote_state.platform.outputs.alb_listener_http_arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.ecs_target.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  condition {
    http_header {
      http_header_name = "X-Product-Id"
      values           = [var.product]
    }
  }
}
