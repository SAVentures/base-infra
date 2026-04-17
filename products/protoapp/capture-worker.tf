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
        # Shared secret is only used by the HTTP /capture endpoint, which
        # stays around for manual triggers. The Kafka path below is what
        # production actually uses.
        { name = "CAPTURE_WORKER_SHARED_SECRET", value = aws_ssm_parameter.capture_worker_shared_secret.value },
        { name = "GEMINI_API_KEY", value = data.aws_ssm_parameter.platform_gemini_api_key.value },
        { name = "S3_BUCKET", value = aws_ssm_parameter.s3_bucket.value },
        { name = "S3_REGION", value = aws_ssm_parameter.s3_region.value },
        { name = "S3_ACCESS_KEY_ID", value = aws_ssm_parameter.s3_access_key_id.value },
        { name = "S3_SECRET_ACCESS_KEY", value = aws_ssm_parameter.s3_secret_access_key.value },
        # Kafka bridge: capture-worker consumes github.capture.requests and
        # publishes github.capture.results. Base-server produces/consumes
        # the other end.
        { name = "KAFKA_BROKERS", value = data.terraform_remote_state.platform.outputs.kafka_bootstrap_servers },
        { name = "KAFKA_CONSUMER_GROUP", value = "capture-worker" },
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

// ---------- Service ----------
//
// Capture-worker has no public exposure. Production invocation is entirely
// over Kafka (see KAFKA_BROKERS above). The ECS Docker health check on
// /health gates the task; nothing on the ALB points here.

resource "aws_ecs_service" "capture_worker" {
  name            = var.capture_worker_service_name
  cluster         = data.terraform_remote_state.platform.outputs.ecs_cluster_id
  desired_count   = 1
  launch_type     = "EC2"
  task_definition = aws_ecs_task_definition.capture_worker.arn
}
