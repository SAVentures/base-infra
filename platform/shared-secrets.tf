// Account-wide secrets shared across all products. Each product's task def
// reads these via data.aws_ssm_parameter at /platform/<category>/<key>.
//
// Values are supplied by Terraform variables, sourced from a gitignored
// `secrets.auto.tfvars`. Rotate by editing that file and running
// `terraform apply` — never via `aws ssm put-parameter`.

resource "aws_ssm_parameter" "shared_resend_api_key" {
  name  = "/platform/email/resend_api_key"
  type  = "SecureString"
  value = var.resend_api_key
}

resource "aws_ssm_parameter" "shared_openai_api_key" {
  name  = "/platform/ai/openai_api_key"
  type  = "SecureString"
  value = var.openai_api_key
}

resource "aws_ssm_parameter" "shared_gemini_api_key" {
  name  = "/platform/ai/gemini_api_key"
  type  = "SecureString"
  value = var.gemini_api_key
}

// No /platform/ai/anthropic_api_key: orca's only Anthropic consumer is the
// content-job script provider, which is opt-in (CONTENT_JOB_SCRIPT_PROVIDER
// defaults to gemini) and treats the key as optional. An SSM parameter holding
// a placeholder reads as configured when it isn't — add it when a real key exists.

// Media-generation providers. Introduced for orca (tickuptoks); placed here
// rather than /orca/* because the accounts are account-wide, not per-product.
resource "aws_ssm_parameter" "shared_fal_api_key" {
  name  = "/platform/ai/fal_api_key"
  type  = "SecureString"
  value = var.fal_api_key
}

resource "aws_ssm_parameter" "shared_elevenlabs_api_key" {
  name  = "/platform/ai/elevenlabs_api_key"
  type  = "SecureString"
  value = var.elevenlabs_api_key
}

// Stripe account keys (publishable is public, secret is account-wide)
resource "aws_ssm_parameter" "shared_stripe_publishable_key" {
  name  = "/platform/payments/stripe_publishable_key"
  type  = "String"
  value = var.stripe_publishable_key
}

resource "aws_ssm_parameter" "shared_stripe_secret_key" {
  name  = "/platform/payments/stripe_secret_key"
  type  = "SecureString"
  value = var.stripe_secret_key
}

// Turnstile (sharing one site key across all hostnames per project decision)
resource "aws_ssm_parameter" "shared_turnstile_site_key" {
  name  = "/platform/auth/turnstile_site_key"
  type  = "String"
  value = var.turnstile_site_key
}

resource "aws_ssm_parameter" "shared_turnstile_secret_key" {
  name  = "/platform/auth/turnstile_secret_key"
  type  = "SecureString"
  value = var.turnstile_secret_key
}

// Media storage SSM params moved to products/protoapp/media-storage.tf on
// 2026-04-16 (now at /protoapp/storage/*). Sjocamp doesn't consume them.
