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

# Current protoapp routing: priority 1, path /api/* only. When launchcamp is
# introduced, this rule's priority drops to 1000 and gains an X-Product-Id
# condition (paired with a matching custom header on protoapp's CloudFront
# distribution). Not changed in this PR to keep the state migration a no-op.
resource "aws_lb_listener_rule" "alb_listener_rule_api_http" {
  listener_arn = data.terraform_remote_state.platform.outputs.alb_listener_http_arn
  priority     = 1

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
