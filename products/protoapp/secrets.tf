# Protoapp product SSM params. Names match the existing AWS resources so
# `terraform import` maps 1:1 with no recreation. Values use `PLACEHOLDER`
# with `ignore_changes = [value]` — after import, state holds the real value
# and Terraform won't try to clobber it.
#
# (Long-term these paths should be flattened to /protoapp/* for consistency
# with /launchcamp/*, but that rename requires a coordinated ECS task def
# update and is deferred.)

resource "aws_ssm_parameter" "db_endpoint" {
  name  = "/db_secrets/protoapp_db_endpoint"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "db_username" {
  name  = "/db_secrets/protoapp_db_username"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/db_secrets/protoapp_db_password"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/db_secrets/protoapp_db_name"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/jwt_secrets/protoapp_jwt_secret"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "google_client_id" {
  name  = "/google_secrets/protoapp_google_client_id"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "google_client_secret" {
  name  = "/google_secrets/protoapp_google_client_secret"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "google_redirect_uri" {
  name  = "/google_secrets/protoapp_google_redirect_uri"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "web_app_uri" {
  name  = "/api_service/protoapp_web_app_uri"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "stripe_publishable_key" {
  name  = "/stripe_secrets/protoapp_stripe_publishable_key"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "stripe_secret_key" {
  name  = "/stripe_secrets/protoapp_stripe_secret_key"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "stripe_webhook_secret" {
  name  = "/stripe_secrets/protoapp_stripe_webhook_secret"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "resend_api_key" {
  name  = "/api_service/protoapp_resend_api_key"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "default_email_sender_address" {
  name  = "/api_service/protoapp_default_email_sender_address"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "gemini_api_key" {
  name  = "/api_service/protoapp_gemini_api_key"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "openai_api_key" {
  name  = "/api_service/protoapp_openai_api_key"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "turnstile_secret_key" {
  name  = "/api_service/protoapp_turnstile_secret_key"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}
