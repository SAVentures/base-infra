// Capture-worker: always-on ECS service that drives Playwright to record
// short demos of commits against the deployed app. Shares the growth-tools-
// media-dev S3 bucket + IAM user with the API service.

// ---------- ECR ----------

resource "aws_ecr_repository" "capture_worker" {
  name                 = var.capture_worker_ecr_repository
  image_tag_mutability = "MUTABLE"
}

// ---------- Log group ----------

resource "aws_cloudwatch_log_group" "capture_worker" {
  name              = "${var.capture_worker_container_name}-logs"
  retention_in_days = 7
}

// ---------- Task definition ----------

resource "aws_ecs_task_definition" "capture_worker" {
  family             = var.capture_worker_container_name
  execution_role_arn = data.terraform_remote_state.platform.outputs.ecs_task_role_arn
  network_mode       = "bridge"

  container_definitions = jsonencode([
    {
      name = var.capture_worker_container_name
      image = "${aws_ecr_repository.capture_worker.repository_url}:${var.capture_worker_image_tag}"
      cpu = 512
      // Soft reservation only — the ECS EC2 node currently has ~620 MB free
      // after the API service. Setting `memory` (hard limit) to 1024 blocked
      // scheduling. Playwright + headless Chromium typically sit around
      // 400-600 MB at idle; this lets it burst above 512 if the node has room.
      memoryReservation = 512
      essential = true

      portMappings = [
        {
          containerPort = 8080
          hostPort      = 0
        }
      ]

      healthCheck = {
        command = [
          "CMD-SHELL",
          "wget -q -O- http://localhost:8080/health || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 20
      }

      environment = [
        { name = "NODE_ENV", value = var.environment },
        { name = "PORT", value = "8080" },
        { name = "APP_URL", value = "https://${var.domain_name}" },
        { name = "APP_EMAIL", value = aws_ssm_parameter.capture_worker_demo_email.value },
        { name = "APP_PASSWORD", value = aws_ssm_parameter.capture_worker_demo_password.value },
        { name = "CAPTURE_WORKER_SHARED_SECRET", value = aws_ssm_parameter.capture_worker_shared_secret.value },
        { name = "GEMINI_API_KEY", value = data.aws_ssm_parameter.platform_gemini_api_key.value },
        { name = "S3_BUCKET", value = aws_ssm_parameter.s3_bucket.value },
        { name = "S3_REGION", value = aws_ssm_parameter.s3_region.value },
        { name = "S3_ACCESS_KEY_ID", value = aws_ssm_parameter.s3_access_key_id.value },
        { name = "S3_SECRET_ACCESS_KEY", value = aws_ssm_parameter.s3_secret_access_key.value },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.capture_worker.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = var.capture_worker_container_name
        }
      }
    }
  ])
}

// ---------- Private exposure (internal ALB) ----------
//
// Capture-worker is reached only from inside the VPC (base-server container
// talks to it via the internal ALB's DNS name). The service still authenticates
// inbound requests with X-Capture-Secret as defense-in-depth, but the network
// boundary now keeps it off the public internet.

resource "aws_security_group" "capture_worker_alb" {
  name        = "capture-worker-internal-alb-sg"
  description = "Allow port 80 from inside the VPC only"
  vpc_id      = data.terraform_remote_state.platform.outputs.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] // VPC CIDR — base-server is the only caller
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "capture_worker_internal" {
  name               = "capture-worker-internal"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.capture_worker_alb.id]
  subnets = [
    data.terraform_remote_state.platform.outputs.private_subnet_ids[0],
    data.terraform_remote_state.platform.outputs.private_subnet_ids[1],
  ]
}

resource "aws_alb_target_group" "capture_worker" {
  name     = "capture-worker-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.terraform_remote_state.platform.outputs.vpc_id

  health_check {
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_listener" "capture_worker_internal_http" {
  load_balancer_arn = aws_lb.capture_worker_internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.capture_worker.arn
  }
}

// ---------- Service ----------

resource "aws_ecs_service" "capture_worker" {
  name            = var.capture_worker_service_name
  cluster         = data.terraform_remote_state.platform.outputs.ecs_cluster_id
  desired_count   = 1
  launch_type     = "EC2"
  task_definition = aws_ecs_task_definition.capture_worker.arn
  iam_role        = data.terraform_remote_state.platform.outputs.ecs_service_role_name

  load_balancer {
    container_name   = var.capture_worker_container_name
    container_port   = 8080
    target_group_arn = aws_alb_target_group.capture_worker.arn
  }

  depends_on = [aws_lb_listener.capture_worker_internal_http]
}
