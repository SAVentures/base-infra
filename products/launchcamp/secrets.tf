# Per-product SSM. Account-wide secrets (resend, openai, gemini, stripe keys,
# turnstile, db creds) live at /platform/* and are read via data.tf.

# Terraform-managed (derived from product/domain)
resource "aws_ssm_parameter" "web_app_uri" {
  name  = "/${var.product}/web_app_uri"
  type  = "String"
  value = "https://${var.domain_name}"
}

resource "aws_ssm_parameter" "google_redirect_uri" {
  name  = "/${var.product}/google_redirect_uri"
  type  = "String"
  value = "https://${var.domain_name}/api/auth/google/callback"
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/${var.product}/db_name"
  type  = "String"
  value = var.product
}

# User-populated (placeholder values — set via aws ssm put-parameter)
resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/${var.product}/jwt_secret"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "google_client_id" {
  name  = "/${var.product}/google_client_id"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "google_client_secret" {
  name  = "/${var.product}/google_client_secret"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "stripe_webhook_secret" {
  name  = "/${var.product}/stripe_webhook_secret"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "default_email_sender_address" {
  name  = "/${var.product}/default_email_sender_address"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}
