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

