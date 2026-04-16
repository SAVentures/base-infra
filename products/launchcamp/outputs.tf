output "webapp_s3_bucket" {
  value = aws_s3_bucket.webapp.id
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.webapp.id
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.webapp.domain_name
}

output "api_target_group_arn" {
  value = aws_lb_target_group.api.arn
}

output "api_log_group_name" {
  value = aws_cloudwatch_log_group.api.name
}
