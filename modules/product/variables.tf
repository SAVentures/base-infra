variable "product" {
  description = "Product slug — used in resource names, SSM paths and the X-Product-Id routing header"
  type        = string
}

variable "domain" {
  description = "Fully-qualified domain this product serves. A pure input: nothing derives a hostname from any other source, so moving a product to its own apex is a one-line change."
  type        = string
}

variable "environment" {
  description = "Environment tag applied to product resources"
  type        = string
  default     = "production"
}

variable "tier" {
  description = "prototype = disposable, lives on a subdomain of the umbrella zone. product = real, lives on its own domain."
  type        = string

  validation {
    condition     = contains(["prototype", "product"], var.tier)
    error_message = "tier must be \"prototype\" or \"product\"."
  }
}

variable "umbrella_zone_domain" {
  description = "The umbrella zone (protoapp.xyz). Used only to validate placement."
  type        = string
}

# --- Platform wiring ---

variable "platform_alb_dns_name" {
  type        = string
  description = "Shared ALB DNS name, used as the API origin"
}

variable "platform_alb_listener_arn" {
  type        = string
  description = "Shared HTTP listener ARN to attach this product's rule to"
}

variable "platform_vpc_id" {
  type        = string
  description = "Shared VPC ID for the target group"
}

variable "acm_certificate_arn" {
  type        = string
  description = "Certificate covering this product's domain. Prototypes pass the platform wildcard; products pass their own cert, created in their stack."
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone holding this product's DNS record"
}

variable "cloudfront_cache_policy_id" {
  type        = string
  description = "Shared no-cache policy for /api/*"
}

variable "cloudfront_origin_request_policy_id" {
  type        = string
  description = "Shared origin-request policy for /api/*"
}

variable "cloudfront_spa_function_arn" {
  type        = string
  description = "Shared viewer-request function for SPA routing"
}

# --- Routing ---

variable "alb_rule_priority" {
  description = "ALB listener rule priority. sjocamp 100, meerkat 200, new projects from 300 in steps of 10. AWS rejects duplicates."
  type        = number
}

variable "extra_aliases" {
  description = "Additional CloudFront aliases beyond var.domain. Used during a domain move to serve old and new names simultaneously."
  type        = list(string)
  default     = []
}

variable "manage_dns_record" {
  description = "Whether this module manages the Cloudflare CNAME. False when the record lives in a zone this stack does not own."
  type        = bool
  default     = true
}

# --- Name overrides ---
# Every attribute below forces resource replacement when changed. Existing
# products pass their live names so migration produces a zero-change plan;
# new projects omit them and get the conventional default.

variable "s3_bucket_name" {
  description = "Override the webapp bucket name. Bucket names are cosmetic and need not match the serving domain."
  type        = string
  default     = null
}

variable "target_group_name" {
  description = "Override the ALB target group name"
  type        = string
  default     = null
}

variable "oac_name" {
  description = "Override the CloudFront origin access control name"
  type        = string
  default     = null
}

variable "log_group_name" {
  description = "Override the CloudFront log group name"
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Override log retention. Defaults by tier: prototype 7, product 90."
  type        = number
  default     = null
}

locals {
  s3_bucket_name     = coalesce(var.s3_bucket_name, "protoapp-${var.product}-webapp")
  target_group_name  = coalesce(var.target_group_name, "${var.product}-api-tg")
  oac_name           = coalesce(var.oac_name, "${var.product}-webapp-oac")
  log_group_name     = coalesce(var.log_group_name, "/aws/cloudfront/${var.product}-webapp")
  cloudfront_aliases = concat([var.domain], var.extra_aliases)
  log_retention_days = coalesce(var.log_retention_days, var.tier == "product" ? 90 : 7)
}
