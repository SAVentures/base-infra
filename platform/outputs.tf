output "alb_dns_name" {
  value       = aws_lb.k8s_alb.dns_name
  description = "DNS name of the shared ALB"
}

output "alb_arn" {
  value       = aws_lb.k8s_alb.arn
  description = "ARN of the shared ALB"
}

output "alb_zone_id" {
  value       = aws_lb.k8s_alb.zone_id
  description = "Hosted zone ID of the shared ALB (for Route 53 alias records)"
}

output "alb_listener_http_arn" {
  value       = aws_lb_listener.http_listener.arn
  description = "ARN of the shared HTTP :80 listener; products attach their own listener rules to this"
}

output "vpc_id" {
  value       = aws_vpc.base_vpc.id
  description = "Shared VPC ID"
}

output "public_subnet_ids" {
  value       = [aws_subnet.public_subnet_a.id, aws_subnet.public_subnet_b.id]
  description = "Public subnet IDs (for ECS tasks, ALB)"
}

output "private_subnet_ids" {
  value       = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
  description = "Private subnet IDs (for RDS and other internal-only resources)"
}

output "ecs_cluster_id" {
  value       = aws_ecs_cluster.ecs_cluster.id
  description = "Shared ECS cluster ID (products attach services here)"
}

output "ecs_cluster_name" {
  value       = aws_ecs_cluster.ecs_cluster.name
  description = "Shared ECS cluster name"
}

output "ecs_service_role_name" {
  value       = aws_iam_role.ecs_service_role.name
  description = "IAM role for ECS services to register with the ALB"
}

output "ecs_task_role_arn" {
  value       = aws_iam_role.ecs_task_role.arn
  description = "IAM task execution role ARN"
}

output "kafka_bootstrap_servers" {
  value       = "kafka.base-services.local:9092"
  description = "Internal Kafka endpoint (shared)"
}

# --- Legacy protoapp-only outputs (retained so protoapp stack stays consistent; ignore for new products) ---

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.webapp_distribution.id
  description = "CloudFront distribution ID for the legacy protoapp webapp"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.webapp_distribution.domain_name
  description = "CloudFront domain name for the legacy protoapp webapp"
}

output "webapp_s3_bucket" {
  value       = aws_s3_bucket.webapp_bucket.id
  description = "S3 bucket for the legacy protoapp webapp"
}
