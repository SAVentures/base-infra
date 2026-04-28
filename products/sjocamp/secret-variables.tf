// Sensitive variables backing user-populated aws_ssm_parameter.* resources in
// secrets.tf. Values are supplied via `secrets.auto.tfvars` (gitignored).
// Rotations flow through `terraform apply` — do NOT use `aws ssm put-parameter`.

variable "jwt_secret" {
  type      = string
  sensitive = true
}

variable "google_client_id" {
  type = string
}

variable "google_client_secret" {
  type      = string
  sensitive = true
}

variable "stripe_webhook_secret" {
  type      = string
  sensitive = true
}

variable "stripe_billing_portal_config_id" {
  type        = string
  description = "Stripe Billing Portal configuration ID (bpc_*). Mode-specific — must be a live-mode config in production."
}

variable "resend_webhook_secret" {
  type      = string
  sensitive = true
}

variable "default_email_sender_address" {
  type = string
}
