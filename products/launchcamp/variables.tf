variable "product" {
  description = "Product identifier (used in resource names and SSM paths)"
  type        = string
  default     = "launchcamp"
}

variable "domain_name" {
  description = "Domain served by this product (app subdomain — landing site lives at the apex)"
  type        = string
  default     = "app.launchcamp.xyz"
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
  description = "Cloudflare zone ID for launchcamp.xyz"
  type        = string
  default     = "d0acb7396dd4c732ff6fd1ccc5e514f6"
}

variable "environment" {
  description = "GO_ENV value for the API container"
  type        = string
  default     = "production"
}

variable "alb_rule_priority" {
  description = "Priority for this product's ALB listener rule. Must be unique across products."
  type        = number
  default     = 100
}

variable "container_name_api" {
  description = "Container name in the API task definition"
  type        = string
  default     = "api"
}

variable "service_name_api" {
  description = "ECS service name"
  type        = string
  default     = "launchcamp-api"
}

variable "api_image_tag" {
  description = "ECR image tag to deploy"
  type        = string
  default     = "latest"
}

variable "ecr_repository_name" {
  description = "ECR repository name for this product's API image (Terraform-managed; see ecr.tf)"
  type        = string
  default     = "launchcamp-server"
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
