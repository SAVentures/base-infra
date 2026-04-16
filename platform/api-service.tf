# ECS Service
# Defines the ECS service with desired count, load balancers, and task definition.
resource "aws_ecs_service" "ecs_service" {
  name            = var.service_name_api                        # Service name
  cluster         = aws_ecs_cluster.ecs_cluster.id              # Link to ECS cluster
  desired_count   = 1                                           # Number of tasks to run
  launch_type     = "EC2"                                       # EC2 launch type
  task_definition = aws_ecs_task_definition.task_definition.arn # Reference the task definition
  iam_role        = aws_iam_role.ecs_service_role.name          # ECS service role for permissions

  load_balancer {                                          # Load balancer configuration
    container_name   = var.container_name_api              # Reference the container name
    container_port   = 80                                  # Port on the container
    target_group_arn = aws_alb_target_group.ecs_target.arn # Target group for the load balancer
  }
}

data "aws_ecr_repository" "api_service" {
  name = "base-server"
}
data "aws_ssm_parameter" "db_endpoint" {
  name = aws_ssm_parameter.db_endpoint.name
}
data "aws_ssm_parameter" "db_username" {
  name = aws_ssm_parameter.db_username.name
}
data "aws_ssm_parameter" "db_password" {
  name = aws_ssm_parameter.db_password.name
}
data "aws_ssm_parameter" "db_name" {
  name = aws_ssm_parameter.db_name.name
}

data "aws_ssm_parameter" "jwt_secret" {
  name = aws_ssm_parameter.jwt_secret.name
}

data "aws_ssm_parameter" "google_client_id" {
  name = aws_ssm_parameter.google_client_id.name
}

data "aws_ssm_parameter" "google_client_secret" {
  name = aws_ssm_parameter.google_client_secret.name
}

data "aws_ssm_parameter" "google_redirect_uri" {
  name = aws_ssm_parameter.google_redirect_uri.name
}

data "aws_ssm_parameter" "web_app_uri" {
  name = aws_ssm_parameter.web_app_uri.name
}

data "aws_ssm_parameter" "stripe_secret_key" {
  name = aws_ssm_parameter.stripe_secret_key.name
}

data "aws_ssm_parameter" "stripe_webhook_secret" {
  name = aws_ssm_parameter.stripe_webhook_secret.name
}

data "aws_ssm_parameter" "resend_api_key" {
  name = aws_ssm_parameter.resend_api_key.name
}

data "aws_ssm_parameter" "default_email_sender_address" {
  name = aws_ssm_parameter.default_email_sender_address.name
}

data "aws_ssm_parameter" "gemini_api_key" {
  name = aws_ssm_parameter.gemini_api_key.name
}

data "aws_ssm_parameter" "openai_api_key" {
  name = aws_ssm_parameter.openai_api_key.name
}

data "aws_ssm_parameter" "turnstile_secret_key" {
  name = aws_ssm_parameter.turnstile_secret_key.name
}

# ECS Task Definition
# Defines the ECS task, including its execution role, container details, and logging configuration.
resource "aws_ecs_task_definition" "task_definition" {
  family             = "base-server"                  # Task family
  execution_role_arn = aws_iam_role.ecs_task_role.arn # Role for ECS task execution
  network_mode       = "bridge"                       # Use bridge networking
  container_definitions = jsonencode([
    {
      name      = var.container_name_api                                         # Container name
      image     = "${data.aws_ecr_repository.api_service.repository_url}:latest" # Docker image to run in ECS
      cpu       = 256                                                            # CPU units (~12.5% of t3.small)
      memory    = 256                                                            # Memory in MB (~12.5% of t3.small)
      essential = true                                                           # Is this container essential to the task?
      portMappings = [
        {
          containerPort = 80 # Inside the container
          hostPort      = 0  # Dynamic port on host
        }
      ]
      # Health check configuration
      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:80/health || exit 1" # Command to check if the container is healthy
        ]
        interval    = 30 # Time (in seconds) between health checks
        timeout     = 5  # Time (in seconds) to wait for a response before considering it a failure
        retries     = 3  # Number of retries before marking the container as unhealthy
        startPeriod = 2  # Optional grace period (in seconds) to wait before health checks start
      }
      environment = [ # Environment variables
        {
          name  = "GO_ENV"
          value = var.environment
        },
        {
          name  = "GIN_MODE"
          value = "release"
        },
        {
          name  = "DB_HOST"
          value = data.aws_ssm_parameter.db_endpoint.value
        },
        {
          name  = "DB_USERNAME"
          value = data.aws_ssm_parameter.db_username.value
        },
        {
          name  = "DB_PASSWORD"
          value = data.aws_ssm_parameter.db_password.value
        },
        {
          name  = "DB_NAME"
          value = data.aws_ssm_parameter.db_name.value
        },
        {
          name  = "JWT_SECRET"
          value = data.aws_ssm_parameter.jwt_secret.value
        },
        {
          name  = "GOOGLE_CLIENT_ID"
          value = data.aws_ssm_parameter.google_client_id.value
        },
        {
          name  = "GOOGLE_CLIENT_SECRET"
          value = data.aws_ssm_parameter.google_client_secret.value
        },
        {
          name  = "GOOGLE_REDIRECT_URI"
          value = data.aws_ssm_parameter.google_redirect_uri.value
        },
        {
          name  = "WEBAPP_URI"
          value = data.aws_ssm_parameter.web_app_uri.value
        },
        {
          name  = "SERVER_PORT"
          value = "80"
        },
        {
          name  = "STRIPE_SECRET_KEY"
          value = data.aws_ssm_parameter.stripe_secret_key.value
        },
        {
          name  = "STRIPE_WEBHOOK_SECRET"
          value = data.aws_ssm_parameter.stripe_webhook_secret.value
        },
        {
          name  = "RESEND_API_KEY"
          value = data.aws_ssm_parameter.resend_api_key.value
        },
        {
          name  = "DEFAULT_EMAIL_SENDER_ADDRESS"
          value = data.aws_ssm_parameter.default_email_sender_address.value
        },
        {
          name  = "GOOGLE_AI_API_KEY"
          value = data.aws_ssm_parameter.gemini_api_key.value
        },
        {
          name  = "OPENAI_API_KEY"
          value = data.aws_ssm_parameter.openai_api_key.value
        },
        {
          name  = "KAFKA_BROKERS"
          value = "kafka.base-services.local:9092"
        },
        {
          name  = "TURNSTILE_SECRET_KEY"
          value = data.aws_ssm_parameter.turnstile_secret_key.value
        }
      ]
      logConfiguration = {
        logDriver = "awslogs" # CloudWatch logging
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_log_group.name # Log group name
          awslogs-region        = var.aws_region                              # AWS region for logging
          awslogs-stream-prefix = var.container_name_api                      # Log stream prefix
        }
      }
    }
  ])
}

# CloudWatch Log Group
# Defines a CloudWatch log group for ECS task logging.
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "${var.container_name_api}-logs" # Log group name
  retention_in_days = 7                                # Retention period for logs
}
