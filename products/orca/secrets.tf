// Per-product SSM, under /orca/*.
//
// Secret values are supplied by Terraform variables sourced from a gitignored
// `secrets.auto.tfvars`. Rotate by editing that file and running
// `terraform apply` — never via `aws ssm put-parameter`.
//
// Account-wide secrets (resend, openai, gemini, fal, elevenlabs, stripe keys,
// db master creds) live at /platform/* — see platform/shared-secrets.tf.

// --- Derived from product / domain (always TF-managed) ---

resource "aws_ssm_parameter" "db_name" {
  name  = "/${var.product}/db_name"
  type  = "String"
  value = var.product
}

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

resource "aws_ssm_parameter" "storage_type" {
  name  = "/${var.product}/storage_type"
  type  = "String"
  value = "s3"
}

// --- Secret values sourced from var.* (secrets.auto.tfvars) ---

resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/${var.product}/jwt_secret"
  type  = "SecureString"
  value = var.jwt_secret
}

resource "aws_ssm_parameter" "google_client_id" {
  name  = "/${var.product}/google_client_id"
  type  = "String"
  value = var.google_client_id
}

resource "aws_ssm_parameter" "google_client_secret" {
  name  = "/${var.product}/google_client_secret"
  type  = "SecureString"
  value = var.google_client_secret
}

resource "aws_ssm_parameter" "stripe_webhook_secret" {
  name  = "/${var.product}/stripe_webhook_secret"
  type  = "SecureString"
  value = var.stripe_webhook_secret
}

// SSM rejects an empty parameter value, and the app treats an unset billing
// portal config as "use the Stripe account default" — so an empty variable
// means no parameter rather than a parameter holding "".
resource "aws_ssm_parameter" "stripe_billing_portal_config_id" {
  count = var.stripe_billing_portal_config_id == "" ? 0 : 1

  name  = "/${var.product}/stripe_billing_portal_config_id"
  type  = "String"
  value = var.stripe_billing_portal_config_id
}

resource "aws_ssm_parameter" "resend_webhook_secret" {
  name  = "/${var.product}/resend_webhook_secret"
  type  = "SecureString"
  value = var.resend_webhook_secret
}

resource "aws_ssm_parameter" "default_email_sender_address" {
  name  = "/${var.product}/default_email_sender_address"
  type  = "String"
  value = var.default_email_sender_address
}

// --- Sentry (stubbed; see secret-variables.tf) ---
//
// count on emptiness matches stripe_billing_portal_config_id above: SSM rejects
// an empty value, and an absent parameter is the honest representation of
// "not configured" — a parameter holding "" reads as configured when it isn't.

resource "aws_ssm_parameter" "sentry_webapp_dsn" {
  count = var.sentry_webapp_dsn == "" ? 0 : 1

  name  = "/${var.product}/sentry/webapp_dsn"
  type  = "String"
  value = var.sentry_webapp_dsn
}

resource "aws_ssm_parameter" "sentry_auth_token" {
  count = var.sentry_auth_token == "" ? 0 : 1

  name  = "/${var.product}/sentry/auth_token"
  type  = "SecureString"
  value = var.sentry_auth_token
}

resource "aws_ssm_parameter" "sentry_org" {
  count = var.sentry_org == "" ? 0 : 1

  name  = "/${var.product}/sentry/org"
  type  = "String"
  value = var.sentry_org
}

resource "aws_ssm_parameter" "sentry_webapp_project" {
  count = var.sentry_webapp_project == "" ? 0 : 1

  name  = "/${var.product}/sentry/webapp_project"
  type  = "String"
  value = var.sentry_webapp_project
}
