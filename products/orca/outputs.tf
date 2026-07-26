output "webapp_s3_bucket" {
  value = module.product.webapp_bucket_id
}

output "cloudfront_distribution_id" {
  value = module.product.cloudfront_distribution_id
}

output "cloudfront_domain_name" {
  value = module.product.cloudfront_domain_name
}

output "api_target_group_arn" {
  value = module.product.target_group_arn
}

output "media_bucket" {
  value = aws_s3_bucket.media.id
}

output "api_ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "render_service_ecr_repository_url" {
  value = aws_ecr_repository.render_service.repository_url
}
