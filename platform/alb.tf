resource "aws_lb" "k8s_alb" {
  name               = "k8sALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]

  enable_deletion_protection = false

  tags = {
    Name = "Default LoadBalancer"
  }
}

# HTTP Listener for CloudFront -> ALB communication
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.k8s_alb.arn
  port              = 80
  protocol          = "HTTP"

  # Default action returns 404 - API paths are handled by listener rules
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_alb_target_group" "ecs_target" {
  name     = "ecs-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.base_vpc.id

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

# Webapp target group removed - webapp now served via S3/CloudFront
# See s3-cloudfront.tf for webapp hosting configuration

# ALB Listener Rule for API (HTTP - for CloudFront)
resource "aws_lb_listener_rule" "alb_listener_rule_api_http" {
  listener_arn = aws_lb_listener.http_listener.id
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
