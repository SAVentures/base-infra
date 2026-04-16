variable "cloudflare_email" {
  description = "email"
  type        = string
  default     = "ryan.cyrus@Live.com"
}
variable "cloudflare_api_key" {
  description = "api key"
  type        = string
  default     = "d41ab9728ae6757d3671289abecc01398ae6e"
}
variable "cloudflare_zone_id" {
  description = "zone id"
  type        = string
  default     = "e1fcf5e6c9b60043f75049228a8e3088"
}
variable "domain_name" {
  description = "domain"
  type        = string
  default     = "protoapp.xyz"
}

variable "aws_region" {
  description = "aws region"
  type        = string
  default     = "us-east-1"
}

variable "container_name_api" {
  description = "container name"
  type        = string
  default     = "api"
}

variable "service_name_api" {
  description = "service name"
  type        = string
  default     = "api_service"
}

variable "container_name_webapp" {
  description = "container name"
  type        = string
  default     = "webapp"
}

variable "service_name_webapp" {
  description = "service name"
  type        = string
  default     = "webapp_service"
}

variable "environment" {
  default = "production"
}

variable "google_client_secret" {
  default = ""
}


variable "stripe_secret_key" {
  default = ""
}

variable "stripe_webhook_secret" {
  default = ""
}

variable "resend_api_key" {
  default = ""
}

variable "default_email_sender_address" {
  default = ""
}


variable "gemini_api_key" {
  default = ""
}

variable "openai_api_key" {
  default = ""
}

variable "turnstile_secret_key" {
  default = ""
}
