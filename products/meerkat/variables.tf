variable "product" {
  description = "Product identifier (used in resource names, SSM paths and the X-Product-Id header)"
  type        = string
  default     = "meerkat"
}

variable "domain_name" {
  description = "Apex domain served by this product"
  type        = string
  default     = "protoapp.xyz"
}

variable "aws_region" {
  description = "AWS region (must match platform)"
  type        = string
  default     = "us-east-1"
}

variable "display_name" {
  description = "Human-facing product name (used in the SSM manifest the app repo reads)"
  type        = string
  default     = "Meerkat"
}

variable "landing_domain" {
  description = "Apex domain serving this product (meerkat has no separate landing — same as app)"
  type        = string
  default     = "protoapp.xyz"
}

variable "cloudflare_email" {
  description = "Cloudflare account email"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for protoapp.xyz"
  type        = string
  default     = "e1fcf5e6c9b60043f75049228a8e3088"
}

variable "environment" {
  description = "GO_ENV value for the API container"
  type        = string
  default     = "production"
}

variable "container_name_api" {
  description = "Container name in the API task definition"
  type        = string
  default     = "api"
}

variable "service_name_api" {
  description = "ECS service name"
  type        = string
  default     = "api_service"
}

variable "api_image_tag" {
  description = "ECR image tag to deploy"
  type        = string
  default     = "latest"
}

variable "ecr_repository_name" {
  description = "ECR repository holding the API image"
  type        = string
  default     = "base-server"
}

# Deliberately NOT renamed to meerkat-capture-worker. ECR repository names are
# ForceNew: renaming destroys the repository and every image in it, leaving the
# capture worker undeployable until CI pushes a fresh image. The name is
# internal and invisible to users, so the rename buys nothing.
variable "capture_worker_ecr_repository" {
  description = "ECR repository holding the capture-worker image. Keeps the protoapp- prefix on purpose; see comment above."
  type        = string
  default     = "protoapp-capture-worker"
}

variable "capture_worker_service_name" {
  description = "ECS service name for the capture-worker"
  type        = string
  default     = "capture_worker_service"
}

variable "capture_worker_container_name" {
  description = "Container name in the capture-worker task definition"
  type        = string
  default     = "capture-worker"
}

variable "capture_worker_image_tag" {
  description = "ECR image tag to deploy for the capture-worker"
  type        = string
  default     = "latest"
}
