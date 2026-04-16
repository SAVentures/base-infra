# Per-product SSM. Account-wide secrets (resend, openai, gemini, stripe keys,
# turnstile, db creds) live at /platform/* and are read via data.tf.

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

resource "aws_ssm_parameter" "stripe_webhook_secret" {
  name  = "/stripe_secrets/protoapp_stripe_webhook_secret"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "default_email_sender_address" {
  name  = "/api_service/protoapp_default_email_sender_address"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}
