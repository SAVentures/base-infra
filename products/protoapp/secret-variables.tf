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

// --- Media storage (bucket name, keys, public URL base) ---

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

// --- Capture worker ---

variable "capture_worker_shared_secret" {
  description = "Shared secret required on every request to the capture-worker via X-Capture-Secret header"
  type        = string
  sensitive   = true
}

variable "capture_worker_demo_email" {
  description = "Email of the seeded test-login user the capture-worker authenticates as"
  type        = string
}

variable "capture_worker_demo_password" {
  description = "Password of the seeded test-login user the capture-worker authenticates as"
  type        = string
  sensitive   = true
}

// --- GitHub OAuth App ---

variable "github_oauth_client_id" {
  description = "Client ID of the GitHub OAuth App used for the Repos connection flow"
  type        = string
}

variable "github_oauth_client_secret" {
  description = "Client secret of the GitHub OAuth App"
  type        = string
  sensitive   = true
}
