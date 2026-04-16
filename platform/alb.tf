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

# Shared HTTP listener for CloudFront -> ALB traffic. Products attach their own
# target groups and listener rules (with X-Product-Id header conditions) via
# aws_lb_listener_rule resources in their product stacks.
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.k8s_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}
