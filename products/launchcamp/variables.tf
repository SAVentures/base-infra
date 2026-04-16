variable "product" {
  description = "Product identifier (used in resource names and SSM paths)"
  type        = string
  default     = "launchcamp"
}

variable "domain_name" {
  description = "Apex domain served by this product"
  type        = string
  default     = "launchcamp.xyz"
}

variable "aws_region" {
  description = "AWS region (must match platform)"
  type        = string
  default     = "us-east-1"
}

variable "cloudflare_email" {
  description = "Cloudflare account email"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for this product's domain"
  type        = string
}

variable "alb_rule_priority" {
  description = "Priority for this product's listener rule on the shared ALB. Must be unique across products."
  type        = number
  default     = 100
}

variable "api_container_cpu" {
  description = "CPU units for the API container"
  type        = number
  default     = 256
}

variable "api_container_memory" {
  description = "Memory (MB) for the API container"
  type        = number
  default     = 256
}

variable "api_desired_count" {
  description = "Number of API tasks to run"
  type        = number
  default     = 1
}

variable "ecr_repository_name" {
  description = "ECR repository holding this product's API image"
  type        = string
  default     = "base-server"
}

variable "api_image_tag" {
  description = "Image tag to deploy"
  type        = string
  default     = "latest"
}
