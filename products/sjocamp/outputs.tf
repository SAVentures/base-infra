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
