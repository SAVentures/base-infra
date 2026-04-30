# Single source of truth for product metadata that the application repo's
# CI workflows need at deploy time (ECR repo, ECS cluster/service, S3 bucket,
# CloudFront distribution id, SSM path prefixes, domains). The app repo reads
# /<product>/manifest via `aws ssm get-parameter` after authenticating via
# OIDC — no duplication, no drift.

resource "aws_ssm_parameter" "manifest" {
  name = "/${var.product}/manifest"
  type = "String"
  tier = "Advanced" # value can exceed 4KB as more products/fields land
  value = jsonencode({
    name = var.display_name
    slug = var.product
    domains = {
      app     = var.domain_name
      landing = var.landing_domain
    }
    aws = {
      region                   = var.aws_region
      ecrRepository            = aws_ecr_repository.api.name
      ecsCluster               = data.terraform_remote_state.platform.outputs.ecs_cluster_name
      ecsService               = aws_ecs_service.api.name
      webappS3Bucket           = aws_s3_bucket.webapp_bucket.id
      cloudfrontDistributionId = aws_cloudfront_distribution.webapp_distribution.id
    }
    ssm = {
      productPrefix  = "/${var.product}"
      platformPrefix = "/platform"
    }
    sentry = {
      org           = var.sentry_org
      webappProject = var.sentry_webapp_project
    }
  })
}
