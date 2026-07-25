variable "product" {
  description = "Product slug — also the subdomain label, the X-Product-Id routing header value, and the SSM path prefix"
  type        = string
  default     = "PROJECT_SLUG"
}

variable "aws_region" {
  description = "AWS region (must match platform)"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment tag applied to product resources"
  type        = string
  default     = "production"
}

variable "cloudflare_email" {
  description = "Cloudflare account email, paired with the global API key from SSM /cloudflare/api_key. Set in the gitignored secrets.auto.tfvars."
  type        = string
}
