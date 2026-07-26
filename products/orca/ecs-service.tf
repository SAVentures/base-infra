resource "aws_cloudwatch_log_group" "api" {
  name              = "/${var.product}/api"
  retention_in_days = module.product.log_retention_days
}

resource "aws_ecs_task_definition" "api" {
  family             = "${var.product}-api"
  execution_role_arn = data.terraform_remote_state.platform.outputs.ecs_task_role_arn
  network_mode       = "bridge"

  # Hosts are Graviton (t4g) — image is built linux/arm64 in CI.
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name              = var.container_name_api
      image             = "${aws_ecr_repository.api.repository_url}:${var.api_image_tag}"
      cpu               = var.api_container_cpu
      memoryReservation = var.api_container_memory_reservation
      memory            = var.api_container_memory
      essential         = true

      portMappings = [
        { containerPort = 80, hostPort = 0 }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }

      environment = [
        { name = "GO_ENV", value = var.environment },
        { name = "GIN_MODE", value = "release" },
        { name = "SERVER_PORT", value = "80" },

        { name = "DB_HOST", value = data.aws_ssm_parameter.rds_host.value },
        { name = "DB_PORT", value = data.aws_ssm_parameter.rds_port.value },
        { name = "DB_USERNAME", value = data.aws_ssm_parameter.platform_db_username.value },
        { name = "DB_PASSWORD", value = data.aws_ssm_parameter.platform_db_password.value },
        { name = "DB_NAME", value = aws_ssm_parameter.db_name.value },

        { name = "JWT_SECRET", value = data.aws_ssm_parameter.jwt_secret.value },
        { name = "GOOGLE_CLIENT_ID", value = data.aws_ssm_parameter.google_client_id.value },
        { name = "GOOGLE_CLIENT_SECRET", value = data.aws_ssm_parameter.google_client_secret.value },
        { name = "GOOGLE_REDIRECT_URI", value = aws_ssm_parameter.google_redirect_uri.value },
        { name = "WEBAPP_URI", value = aws_ssm_parameter.web_app_uri.value },

        { name = "STRIPE_SECRET_KEY", value = data.aws_ssm_parameter.platform_stripe_secret_key.value },
        { name = "STRIPE_WEBHOOK_SECRET", value = data.aws_ssm_parameter.stripe_webhook_secret.value },
        # Read from the variable rather than the SSM parameter: the parameter is
        # conditional (see secrets.tf) and an empty value is the app's documented
        # "use the Stripe account default" signal.
        { name = "STRIPE_BILLING_PORTAL_CONFIG_ID", value = var.stripe_billing_portal_config_id },

        { name = "RESEND_API_KEY", value = data.aws_ssm_parameter.platform_resend_api_key.value },
        { name = "RESEND_WEBHOOK_SECRET", value = data.aws_ssm_parameter.resend_webhook_secret.value },
        { name = "DEFAULT_EMAIL_SENDER_ADDRESS", value = data.aws_ssm_parameter.default_email_sender_address.value },

        { name = "OPENAI_API_KEY", value = data.aws_ssm_parameter.platform_openai_api_key.value },
        { name = "GOOGLE_AI_API_KEY", value = data.aws_ssm_parameter.platform_gemini_api_key.value },
        { name = "FAL_API_KEY", value = data.aws_ssm_parameter.platform_fal_api_key.value },
        { name = "ELEVENLABS_API_KEY", value = data.aws_ssm_parameter.platform_elevenlabs_api_key.value },

        # PRODUCT_NAME is stamped on every Stripe object this server creates and
        # matched against incoming webhook metadata. It is what keeps orca's
        # objects distinct from meerkat's and sjocamp's on the shared Stripe
        # account, so it must equal the slug.
        { name = "PRODUCT_NAME", value = var.product },

        { name = "STORAGE_TYPE", value = aws_ssm_parameter.storage_type.value },
        { name = "S3_BUCKET", value = aws_s3_bucket.media.id },
        { name = "S3_REGION", value = var.aws_region },
        { name = "S3_ACCESS_KEY_ID", value = aws_iam_access_key.media.id },
        { name = "S3_SECRET_ACCESS_KEY", value = aws_iam_access_key.media.secret },
        { name = "MEDIA_PUBLIC_URL_BASE", value = aws_ssm_parameter.media_public_url_base.value },

        { name = "KAFKA_BROKERS", value = data.terraform_remote_state.platform.outputs.kafka_bootstrap_servers },
        { name = "KAFKA_TOPIC", value = "${var.product}.webhook-events" },
        { name = "KAFKA_CONSUMER_GROUP", value = "${var.product}.webhook-consumers" },

        # Render hand-off topics. These MUST stay byte-identical to the
        # render-service side (RENDER_REQUEST_TOPIC/RENDER_RESULT_TOPIC in
        # render-service.tf) — the two services have different variable names
        # for the same topic, so overriding one side alone silently breaks the
        # hand-off with no error on either end.
        { name = "CONTENT_JOB_RENDER_REQUEST_KAFKA_TOPIC", value = local.render_request_topic },
        { name = "CONTENT_JOB_RENDER_RESULT_KAFKA_TOPIC", value = local.render_result_topic },
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
    target_group_arn = module.product.target_group_arn
  }

  depends_on = [module.product]
}
