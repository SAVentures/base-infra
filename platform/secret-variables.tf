// Sensitive variables backing aws_ssm_parameter.shared_* resources.
// Values are supplied via `secrets.auto.tfvars` (gitignored). Rotations flow
// through `terraform apply` — do NOT use `aws ssm put-parameter` anymore.

variable "resend_api_key" {
  type      = string
  sensitive = true
}

variable "openai_api_key" {
  type      = string
  sensitive = true
}

variable "gemini_api_key" {
  type      = string
  sensitive = true
}

variable "stripe_publishable_key" {
  type = string
}

variable "stripe_secret_key" {
  type      = string
  sensitive = true
}

variable "turnstile_site_key" {
  type = string
}

variable "turnstile_secret_key" {
  type      = string
  sensitive = true
}

variable "s3_bucket" {
  type = string
}

variable "s3_region" {
  type = string
}

variable "s3_access_key_id" {
  type      = string
  sensitive = true
}

variable "s3_secret_access_key" {
  type      = string
  sensitive = true
}

variable "media_public_url_base" {
  type = string
}
