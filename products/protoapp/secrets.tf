// Per-product SSM, under /protoapp/*.
//
// Secret values are supplied by Terraform variables sourced from a gitignored
// `secrets.auto.tfvars`. Rotate by editing that file and running
// `terraform apply` — never via `aws ssm put-parameter`.
//
// Account-wide secrets (resend, openai, gemini, stripe keys, turnstile, db
// master creds) live at /platform/* — see platform/shared-secrets.tf.

// Import blocks adopt already-populated /protoapp/* params into state on first
// apply after the original refactor. No-op on subsequent applies.

import {
  to = aws_ssm_parameter.db_name
  id = "/protoapp/db_name"
}
import {
  to = aws_ssm_parameter.jwt_secret
  id = "/protoapp/jwt_secret"
}
import {
  to = aws_ssm_parameter.google_client_id
  id = "/protoapp/google_client_id"
}
import {
  to = aws_ssm_parameter.google_client_secret
  id = "/protoapp/google_client_secret"
}
import {
  to = aws_ssm_parameter.google_redirect_uri
  id = "/protoapp/google_redirect_uri"
}
import {
  to = aws_ssm_parameter.web_app_uri
  id = "/protoapp/web_app_uri"
}
import {
  to = aws_ssm_parameter.stripe_webhook_secret
  id = "/protoapp/stripe_webhook_secret"
}
import {
  to = aws_ssm_parameter.default_email_sender_address
  id = "/protoapp/default_email_sender_address"
}

// --- Derived from product / domain (always TF-managed) ---

resource "aws_ssm_parameter" "db_name" {
  name  = "/${var.product}/db_name"
  type  = "String"
  value = "base_db" // growth-tools app expects this specific DB name
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

resource "aws_ssm_parameter" "oauth_redirect_base" {
  name  = "/${var.product}/oauth_redirect_base"
  type  = "String"
  value = "https://${var.domain_name}"
}

resource "aws_ssm_parameter" "storage_type" {
  name  = "/${var.product}/storage_type"
  type  = "String"
  value = "s3" // flip to "local" per-product if you don't want S3 media
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

resource "aws_ssm_parameter" "default_email_sender_address" {
  name  = "/${var.product}/default_email_sender_address"
  type  = "String"
  value = var.default_email_sender_address
}

// --- Social platform + integration credentials ---

resource "aws_ssm_parameter" "x_api_key" {
  name  = "/${var.product}/x_api_key"
  type  = "SecureString"
  value = var.x_api_key
}

resource "aws_ssm_parameter" "x_api_secret" {
  name  = "/${var.product}/x_api_secret"
  type  = "SecureString"
  value = var.x_api_secret
}

resource "aws_ssm_parameter" "linkedin_client_id" {
  name  = "/${var.product}/linkedin_client_id"
  type  = "String"
  value = var.linkedin_client_id
}

resource "aws_ssm_parameter" "linkedin_client_secret" {
  name  = "/${var.product}/linkedin_client_secret"
  type  = "SecureString"
  value = var.linkedin_client_secret
}

resource "aws_ssm_parameter" "meta_app_id" {
  name  = "/${var.product}/meta_app_id"
  type  = "String"
  value = var.meta_app_id
}

resource "aws_ssm_parameter" "meta_app_secret" {
  name  = "/${var.product}/meta_app_secret"
  type  = "SecureString"
  value = var.meta_app_secret
}

resource "aws_ssm_parameter" "threads_app_id" {
  name  = "/${var.product}/threads_app_id"
  type  = "String"
  value = var.threads_app_id
}

resource "aws_ssm_parameter" "threads_app_secret" {
  name  = "/${var.product}/threads_app_secret"
  type  = "SecureString"
  value = var.threads_app_secret
}

resource "aws_ssm_parameter" "threads_access_token" {
  name  = "/${var.product}/threads_access_token"
  type  = "SecureString"
  value = var.threads_access_token
}

resource "aws_ssm_parameter" "tiktok_client_key" {
  name  = "/${var.product}/tiktok_client_key"
  type  = "String"
  value = var.tiktok_client_key
}

resource "aws_ssm_parameter" "tiktok_client_secret" {
  name  = "/${var.product}/tiktok_client_secret"
  type  = "SecureString"
  value = var.tiktok_client_secret
}

resource "aws_ssm_parameter" "pinterest_app_id" {
  name  = "/${var.product}/pinterest_app_id"
  type  = "String"
  value = var.pinterest_app_id
}

resource "aws_ssm_parameter" "pinterest_app_secret" {
  name  = "/${var.product}/pinterest_app_secret"
  type  = "SecureString"
  value = var.pinterest_app_secret
}

resource "aws_ssm_parameter" "github_webhook_secret" {
  name  = "/${var.product}/github_webhook_secret"
  type  = "SecureString"
  value = var.github_webhook_secret
}

// --- Capture worker ---

resource "aws_ssm_parameter" "capture_worker_shared_secret" {
  name  = "/${var.product}/capture_worker/shared_secret"
  type  = "SecureString"
  value = var.capture_worker_shared_secret
}

resource "aws_ssm_parameter" "capture_worker_demo_email" {
  name  = "/${var.product}/capture_worker/demo_email"
  type  = "String"
  value = var.capture_worker_demo_email
}

resource "aws_ssm_parameter" "capture_worker_demo_password" {
  name  = "/${var.product}/capture_worker/demo_password"
  type  = "SecureString"
  value = var.capture_worker_demo_password
}
