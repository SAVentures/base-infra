data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket = "protoapp-infra-terraform-state"
    key    = "state/terraform.tfstate"
    region = var.aws_region
  }
}

data "aws_ecr_repository" "api" {
  name = var.ecr_repository_name
}

# --- Platform-shared (account-wide secrets, single source of truth in /platform/*) ---

data "aws_ssm_parameter" "rds_endpoint" {
  name = "/platform/rds/endpoint"
}

data "aws_ssm_parameter" "platform_db_username" {
  name = "/platform/rds/master_username"
}

data "aws_ssm_parameter" "platform_db_password" {
  name = "/platform/rds/master_password"
}

data "aws_ssm_parameter" "platform_resend_api_key" {
  name = "/platform/email/resend_api_key"
}

data "aws_ssm_parameter" "platform_openai_api_key" {
  name = "/platform/ai/openai_api_key"
}

data "aws_ssm_parameter" "platform_gemini_api_key" {
  name = "/platform/ai/gemini_api_key"
}

data "aws_ssm_parameter" "platform_stripe_secret_key" {
  name = "/platform/payments/stripe_secret_key"
}

data "aws_ssm_parameter" "platform_turnstile_secret_key" {
  name = "/platform/auth/turnstile_secret_key"
}

# --- Product-owned (per-product secrets) ---

data "aws_ssm_parameter" "db_name" {
  name       = aws_ssm_parameter.db_name.name
  depends_on = [aws_ssm_parameter.db_name]
}

data "aws_ssm_parameter" "jwt_secret" {
  name       = aws_ssm_parameter.jwt_secret.name
  depends_on = [aws_ssm_parameter.jwt_secret]
}

data "aws_ssm_parameter" "google_client_id" {
  name       = aws_ssm_parameter.google_client_id.name
  depends_on = [aws_ssm_parameter.google_client_id]
}

data "aws_ssm_parameter" "google_client_secret" {
  name       = aws_ssm_parameter.google_client_secret.name
  depends_on = [aws_ssm_parameter.google_client_secret]
}

data "aws_ssm_parameter" "google_redirect_uri" {
  name       = aws_ssm_parameter.google_redirect_uri.name
  depends_on = [aws_ssm_parameter.google_redirect_uri]
}

data "aws_ssm_parameter" "web_app_uri" {
  name       = aws_ssm_parameter.web_app_uri.name
  depends_on = [aws_ssm_parameter.web_app_uri]
}

data "aws_ssm_parameter" "stripe_webhook_secret" {
  name       = aws_ssm_parameter.stripe_webhook_secret.name
  depends_on = [aws_ssm_parameter.stripe_webhook_secret]
}

data "aws_ssm_parameter" "default_email_sender_address" {
  name       = aws_ssm_parameter.default_email_sender_address.name
  depends_on = [aws_ssm_parameter.default_email_sender_address]
}

# --- Social platform + integration credentials ---

data "aws_ssm_parameter" "x_api_key" {
  name       = aws_ssm_parameter.x_api_key.name
  depends_on = [aws_ssm_parameter.x_api_key]
}

data "aws_ssm_parameter" "x_api_secret" {
  name       = aws_ssm_parameter.x_api_secret.name
  depends_on = [aws_ssm_parameter.x_api_secret]
}

data "aws_ssm_parameter" "linkedin_client_id" {
  name       = aws_ssm_parameter.linkedin_client_id.name
  depends_on = [aws_ssm_parameter.linkedin_client_id]
}

data "aws_ssm_parameter" "linkedin_client_secret" {
  name       = aws_ssm_parameter.linkedin_client_secret.name
  depends_on = [aws_ssm_parameter.linkedin_client_secret]
}

data "aws_ssm_parameter" "meta_app_id" {
  name       = aws_ssm_parameter.meta_app_id.name
  depends_on = [aws_ssm_parameter.meta_app_id]
}

data "aws_ssm_parameter" "meta_app_secret" {
  name       = aws_ssm_parameter.meta_app_secret.name
  depends_on = [aws_ssm_parameter.meta_app_secret]
}

data "aws_ssm_parameter" "threads_app_id" {
  name       = aws_ssm_parameter.threads_app_id.name
  depends_on = [aws_ssm_parameter.threads_app_id]
}

data "aws_ssm_parameter" "threads_app_secret" {
  name       = aws_ssm_parameter.threads_app_secret.name
  depends_on = [aws_ssm_parameter.threads_app_secret]
}

data "aws_ssm_parameter" "threads_access_token" {
  name       = aws_ssm_parameter.threads_access_token.name
  depends_on = [aws_ssm_parameter.threads_access_token]
}

data "aws_ssm_parameter" "tiktok_client_key" {
  name       = aws_ssm_parameter.tiktok_client_key.name
  depends_on = [aws_ssm_parameter.tiktok_client_key]
}

data "aws_ssm_parameter" "tiktok_client_secret" {
  name       = aws_ssm_parameter.tiktok_client_secret.name
  depends_on = [aws_ssm_parameter.tiktok_client_secret]
}

data "aws_ssm_parameter" "pinterest_app_id" {
  name       = aws_ssm_parameter.pinterest_app_id.name
  depends_on = [aws_ssm_parameter.pinterest_app_id]
}

data "aws_ssm_parameter" "pinterest_app_secret" {
  name       = aws_ssm_parameter.pinterest_app_secret.name
  depends_on = [aws_ssm_parameter.pinterest_app_secret]
}

data "aws_ssm_parameter" "github_webhook_secret" {
  name       = aws_ssm_parameter.github_webhook_secret.name
  depends_on = [aws_ssm_parameter.github_webhook_secret]
}

data "aws_ssm_parameter" "oauth_redirect_base" {
  name       = aws_ssm_parameter.oauth_redirect_base.name
  depends_on = [aws_ssm_parameter.oauth_redirect_base]
}
