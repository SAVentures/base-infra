# Terraform declares every SSM parameter this product needs so they're
# tracked as resources. For secrets the user fills in (OAuth client_secret,
# Stripe keys, etc.), the value is `PLACEHOLDER` and ignore_changes prevents
# Terraform from clobbering the real value once set.
# Non-secret params (redirect URIs, webapp URI, product DB name) are managed
# by Terraform fully.

# --- Managed by Terraform (derived from domain/product) ---

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

# --- User-populated (placeholder values; ignore_changes preserves real values) ---

resource "aws_ssm_parameter" "db_username" {
  name  = "/${var.product}/db_username"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.product}/db_password"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

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

resource "aws_ssm_parameter" "stripe_publishable_key" {
  name  = "/${var.product}/stripe_publishable_key"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "stripe_secret_key" {
  name  = "/${var.product}/stripe_secret_key"
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

resource "aws_ssm_parameter" "resend_api_key" {
  name  = "/${var.product}/resend_api_key"
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

resource "aws_ssm_parameter" "gemini_api_key" {
  name  = "/${var.product}/gemini_api_key"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "openai_api_key" {
  name  = "/${var.product}/openai_api_key"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "turnstile_secret_key" {
  name  = "/${var.product}/turnstile_secret_key"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "turnstile_site_key" {
  name  = "/${var.product}/turnstile_site_key"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}
