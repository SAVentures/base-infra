resource "aws_cloudwatch_log_group" "api" {
  name              = "/${var.product}/api"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "api" {
  family             = "${var.product}-api"
  execution_role_arn = data.terraform_remote_state.platform.outputs.ecs_task_role_arn
  network_mode       = "bridge"

  container_definitions = jsonencode([
    {
      name      = var.container_name_api
      image     = "${data.aws_ecr_repository.api.repository_url}:${var.api_image_tag}"
      cpu       = var.api_container_cpu
      memory    = var.api_container_memory
      essential = true

      portMappings = [
        { containerPort = 80, hostPort = 0 }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 2
      }

      environment = [
        { name = "GO_ENV", value = var.environment },
        { name = "GIN_MODE", value = "release" },
        { name = "SERVER_PORT", value = "80" },
        { name = "DB_HOST", value = data.aws_ssm_parameter.rds_host.value },
        { name = "DB_USERNAME", value = data.aws_ssm_parameter.db_username.value },
        { name = "DB_PASSWORD", value = data.aws_ssm_parameter.db_password.value },
        { name = "DB_NAME", value = aws_ssm_parameter.db_name.value },
        { name = "JWT_SECRET", value = data.aws_ssm_parameter.jwt_secret.value },
        { name = "GOOGLE_CLIENT_ID", value = data.aws_ssm_parameter.google_client_id.value },
        { name = "GOOGLE_CLIENT_SECRET", value = data.aws_ssm_parameter.google_client_secret.value },
        { name = "GOOGLE_REDIRECT_URI", value = aws_ssm_parameter.google_redirect_uri.value },
        { name = "WEBAPP_URI", value = aws_ssm_parameter.web_app_uri.value },
        { name = "STRIPE_SECRET_KEY", value = data.aws_ssm_parameter.stripe_secret_key.value },
        { name = "STRIPE_WEBHOOK_SECRET", value = data.aws_ssm_parameter.stripe_webhook_secret.value },
        { name = "RESEND_API_KEY", value = data.aws_ssm_parameter.resend_api_key.value },
        { name = "DEFAULT_EMAIL_SENDER_ADDRESS", value = data.aws_ssm_parameter.default_email_sender_address.value },
        { name = "GOOGLE_AI_API_KEY", value = data.aws_ssm_parameter.gemini_api_key.value },
        { name = "OPENAI_API_KEY", value = data.aws_ssm_parameter.openai_api_key.value },
        { name = "TURNSTILE_SECRET_KEY", value = data.aws_ssm_parameter.turnstile_secret_key.value },
        { name = "KAFKA_BROKERS", value = data.terraform_remote_state.platform.outputs.kafka_bootstrap_servers },
        { name = "KAFKA_TOPIC", value = "${var.product}.webhook-events" },
        { name = "KAFKA_CONSUMER_GROUP", value = "${var.product}.webhook-consumers" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.api.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = var.container_name_api
        }
      }
    }
  ])
}

resource "aws_ecs_service" "api" {
  name            = var.service_name_api
  cluster         = data.terraform_remote_state.platform.outputs.ecs_cluster_id
  desired_count   = var.api_desired_count
  launch_type     = "EC2"
  task_definition = aws_ecs_task_definition.api.arn
  iam_role        = data.terraform_remote_state.platform.outputs.ecs_service_role_name

  load_balancer {
    container_name   = var.container_name_api
    container_port   = 80
    target_group_arn = aws_lb_target_group.api.arn
  }

  depends_on = [aws_lb_listener_rule.api]
}
