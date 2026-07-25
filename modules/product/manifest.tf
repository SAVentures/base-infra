# Machine-readable product descriptor consumed by app repos and CI so deploy
# workflows need no hardcoded ids.
resource "aws_ssm_parameter" "manifest" {
  name = "/${var.product}/manifest"
  type = "String"
  tier = "Advanced"
  value = jsonencode({
    name = var.display_name
    slug = var.product
    domains = {
      app = var.domain
    }
    aws = {
      region                   = var.aws_region
      webappS3Bucket           = aws_s3_bucket.webapp.id
      cloudfrontDistributionId = aws_cloudfront_distribution.webapp.id
    }
    ssm = {
      productPrefix  = "/${var.product}"
      platformPrefix = "/platform"
    }
  })
}
