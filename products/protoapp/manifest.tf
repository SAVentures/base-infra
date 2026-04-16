# See products/launchcamp/manifest.tf for the pattern + rationale.

resource "aws_ssm_parameter" "manifest" {
  name = "/${var.product}/manifest"
  type = "String"
  tier = "Advanced"
  value = jsonencode({
    name = var.display_name
    slug = var.product
    domains = {
      app     = var.domain_name
      landing = var.landing_domain
    }
    aws = {
      region                   = var.aws_region
      ecrRepository            = data.aws_ecr_repository.api.name
      ecsCluster               = data.terraform_remote_state.platform.outputs.ecs_cluster_name
      ecsService               = aws_ecs_service.ecs_service.name
      webappS3Bucket           = aws_s3_bucket.webapp_bucket.id
      cloudfrontDistributionId = aws_cloudfront_distribution.webapp_distribution.id
    }
    ssm = {
      productPrefix  = "/${var.product}"
      platformPrefix = "/platform"
    }
  })
}
