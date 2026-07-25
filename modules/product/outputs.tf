output "target_group_arn" {
  value       = aws_lb_target_group.api.arn
  description = "Attach the product's ECS service to this"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.webapp.id
  description = "For cache invalidation in CI"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.webapp.domain_name
  description = "Distribution hostname, for DNS records managed outside this module"
}

output "webapp_bucket_id" {
  value       = aws_s3_bucket.webapp.id
  description = "Sync built static assets here"
}

output "listener_rule_arn" {
  value       = aws_lb_listener_rule.api.arn
  description = "For ECS services that must depend_on the rule existing"
}
