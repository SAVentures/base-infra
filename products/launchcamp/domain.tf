resource "aws_acm_certificate" "ssl_cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  acm_validation = {
    for dvo in aws_acm_certificate.ssl_cert.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      type    = dvo.resource_record_type
      content = dvo.resource_record_value
    }
  }
}

resource "cloudflare_dns_record" "acm_validation" {
  zone_id = var.cloudflare_zone_id
  name    = trimsuffix(local.acm_validation[var.domain_name].name, ".")
  type    = local.acm_validation[var.domain_name].type
  content = trimsuffix(local.acm_validation[var.domain_name].content, ".")
  ttl     = 1
}

# Single CNAME for app.launchcamp.xyz pointing at this product's CloudFront.
# The apex (launchcamp.xyz) and www are managed elsewhere (landing site on
# Cloudflare Pages) — Terraform here intentionally does not touch them.
resource "cloudflare_dns_record" "app_to_cloudfront" {
  zone_id = var.cloudflare_zone_id
  name    = var.domain_name
  type    = "CNAME"
  content = aws_cloudfront_distribution.webapp_distribution.domain_name
  ttl     = 1
  proxied = false
}

# Zone-wide TLS/HTTP settings are owned by the landing-site setup; not managed
# here so the two stacks don't fight over the same settings.
