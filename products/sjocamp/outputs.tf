output "webapp_s3_bucket" {
  value = aws_s3_bucket.webapp_bucket.id
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.webapp_distribution.id
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.webapp_distribution.domain_name
}

output "api_target_group_arn" {
  value = aws_lb_target_group.api.arn
}
