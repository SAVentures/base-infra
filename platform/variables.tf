variable "aws_region" {
  description = "AWS region for all platform resources"
  type        = string
  default     = "us-east-1"
}

variable "cloudflare_email" {
  description = "Cloudflare account email (paired with the global API key from /cloudflare/api_key)"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the umbrella zone (protoapp.xyz)"
  type        = string
  default     = "e1fcf5e6c9b60043f75049228a8e3088"
}

variable "zone_domain" {
  description = "Umbrella domain hosting all product subdomains"
  type        = string
  default     = "protoapp.xyz"
}
