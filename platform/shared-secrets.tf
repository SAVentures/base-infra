# Account-wide secrets shared across all products. Each product's task def reads
# these via data.aws_ssm_parameter at /platform/<category>/<key>. Values are
# user-populated (PLACEHOLDER + ignore_changes); copy from existing per-product
# paths via `aws ssm put-parameter` after this stack applies.

# Resend (single account)
resource "aws_ssm_parameter" "shared_resend_api_key" {
  name  = "/platform/email/resend_api_key"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

# AI providers (single account each)
resource "aws_ssm_parameter" "shared_openai_api_key" {
  name  = "/platform/ai/openai_api_key"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "shared_gemini_api_key" {
  name  = "/platform/ai/gemini_api_key"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

# Stripe account keys (publishable is public, secret is account-wide)
resource "aws_ssm_parameter" "shared_stripe_publishable_key" {
  name  = "/platform/payments/stripe_publishable_key"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "shared_stripe_secret_key" {
  name  = "/platform/payments/stripe_secret_key"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

# Turnstile (sharing one site key across all hostnames per project decision)
resource "aws_ssm_parameter" "shared_turnstile_site_key" {
  name  = "/platform/auth/turnstile_site_key"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "shared_turnstile_secret_key" {
  name  = "/platform/auth/turnstile_secret_key"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

# --- Media storage (shared S3 bucket + IAM user across products) ---

resource "aws_ssm_parameter" "shared_s3_bucket" {
  name  = "/platform/storage/s3_bucket"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "shared_s3_region" {
  name  = "/platform/storage/s3_region"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "shared_s3_access_key_id" {
  name  = "/platform/storage/s3_access_key_id"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "shared_s3_secret_access_key" {
  name  = "/platform/storage/s3_secret_access_key"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}

resource "aws_ssm_parameter" "shared_media_public_url_base" {
  name  = "/platform/storage/media_public_url_base"
  type  = "String"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}
