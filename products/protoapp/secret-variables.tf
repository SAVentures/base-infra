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

variable "default_email_sender_address" {
  type = string
}

// --- Social platform + integration credentials ---

variable "x_api_key" {
  type      = string
  sensitive = true
}

variable "x_api_secret" {
  type      = string
  sensitive = true
}

variable "linkedin_client_id" {
  type = string
}

variable "linkedin_client_secret" {
  type      = string
  sensitive = true
}

variable "meta_app_id" {
  type = string
}

variable "meta_app_secret" {
  type      = string
  sensitive = true
}

variable "threads_app_id" {
  type = string
}

variable "threads_app_secret" {
  type      = string
  sensitive = true
}

variable "threads_access_token" {
  type      = string
  sensitive = true
}

variable "tiktok_client_key" {
  type = string
}

variable "tiktok_client_secret" {
  type      = string
  sensitive = true
}

variable "pinterest_app_id" {
  type = string
}

variable "pinterest_app_secret" {
  type      = string
  sensitive = true
}

variable "github_webhook_secret" {
  type      = string
  sensitive = true
}
