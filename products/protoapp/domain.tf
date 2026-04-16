resource "aws_acm_certificate" "ssl_cert" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}", "www.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  acm_validation_sans = toset(["*.${var.domain_name}", "www.${var.domain_name}"])
  acm_validation_by_domain = {
    for dvo in aws_acm_certificate.ssl_cert.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
}

resource "cloudflare_record" "acm_validation" {
  for_each = local.acm_validation_sans

  zone_id = var.cloudflare_zone_id
  # Cloudflare stores record names as the subdomain only (zone stripped).
  # AWS ACM gives the FQDN with trailing dot — strip both.
  name  = replace(trimsuffix(local.acm_validation_by_domain[each.key].name, "."), ".${var.domain_name}", "")
  type  = local.acm_validation_by_domain[each.key].type
  value = local.acm_validation_by_domain[each.key].value
  ttl   = 1
}

resource "cloudflare_record" "root_to_cloudfront" {
  zone_id = var.cloudflare_zone_id
  name    = var.domain_name
  type    = "CNAME"
  value   = aws_cloudfront_distribution.webapp_distribution.domain_name
  ttl     = 1
  proxied = false
}

resource "cloudflare_record" "www_to_cloudfront" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  type    = "CNAME"
  value   = aws_cloudfront_distribution.webapp_distribution.domain_name
  ttl     = 1
  proxied = false
}

resource "cloudflare_zone_settings_override" "ssl_tls_settings" {
  zone_id = var.cloudflare_zone_id

  settings {
    ssl              = "strict"
    tls_1_3          = "on"
    min_tls_version  = "1.2"
    always_use_https = "on"
    http3            = "on"
  }
}
