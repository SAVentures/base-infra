data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket = "protoapp-infra-terraform-state"
    key    = "state/terraform.tfstate"
    region = var.aws_region
  }
}

data "aws_ssm_parameter" "rds_host" {
  name = "/platform/rds/host"
}

data "aws_ssm_parameter" "db_username" {
  name       = aws_ssm_parameter.db_username.name
  depends_on = [aws_ssm_parameter.db_username]
}

data "aws_ssm_parameter" "db_password" {
  name       = aws_ssm_parameter.db_password.name
  depends_on = [aws_ssm_parameter.db_password]
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

data "aws_ssm_parameter" "stripe_secret_key" {
  name       = aws_ssm_parameter.stripe_secret_key.name
  depends_on = [aws_ssm_parameter.stripe_secret_key]
}

data "aws_ssm_parameter" "stripe_webhook_secret" {
  name       = aws_ssm_parameter.stripe_webhook_secret.name
  depends_on = [aws_ssm_parameter.stripe_webhook_secret]
}

data "aws_ssm_parameter" "resend_api_key" {
  name       = aws_ssm_parameter.resend_api_key.name
  depends_on = [aws_ssm_parameter.resend_api_key]
}

data "aws_ssm_parameter" "default_email_sender_address" {
  name       = aws_ssm_parameter.default_email_sender_address.name
  depends_on = [aws_ssm_parameter.default_email_sender_address]
}

data "aws_ssm_parameter" "gemini_api_key" {
  name       = aws_ssm_parameter.gemini_api_key.name
  depends_on = [aws_ssm_parameter.gemini_api_key]
}

data "aws_ssm_parameter" "openai_api_key" {
  name       = aws_ssm_parameter.openai_api_key.name
  depends_on = [aws_ssm_parameter.openai_api_key]
}

data "aws_ssm_parameter" "turnstile_secret_key" {
  name       = aws_ssm_parameter.turnstile_secret_key.name
  depends_on = [aws_ssm_parameter.turnstile_secret_key]
}
