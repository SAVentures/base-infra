resource "aws_lb_target_group" "api" {
  name        = "${var.product}-api-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.platform.outputs.vpc_id
  target_type = "instance"

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

# Route requests to this product's target group based on the X-Product-Id
# header injected by this product's CloudFront distribution. Priority must be
# unique across products sharing the ALB.
resource "aws_lb_listener_rule" "api" {
  listener_arn = data.terraform_remote_state.platform.outputs.alb_listener_http_arn
  priority     = var.alb_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  condition {
    http_header {
      http_header_name = "X-Product-Id"
      values           = [var.product]
    }
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}
