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
      name    = dvo.resource_record_name
      type    = dvo.resource_record_type
      content = dvo.resource_record_value
    }
  }
}

resource "cloudflare_dns_record" "acm_validation" {
  for_each = local.acm_validation_sans

  zone_id = var.cloudflare_zone_id
  name    = trimsuffix(local.acm_validation_by_domain[each.key].name, ".")
  type    = local.acm_validation_by_domain[each.key].type
  content = trimsuffix(local.acm_validation_by_domain[each.key].content, ".")
  ttl     = 1
}

resource "cloudflare_dns_record" "root_to_cloudfront" {
  zone_id = var.cloudflare_zone_id
  name    = var.domain_name
  type    = "CNAME"
  content = aws_cloudfront_distribution.webapp_distribution.domain_name
  ttl     = 1
  proxied = false
}

resource "cloudflare_dns_record" "www_to_cloudfront" {
  zone_id = var.cloudflare_zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  content = aws_cloudfront_distribution.webapp_distribution.domain_name
  ttl     = 1
  proxied = false
}

# v5 splits zone-wide settings into one resource per setting_id.
resource "cloudflare_zone_setting" "ssl" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "ssl"
  value      = "strict"
}

resource "cloudflare_zone_setting" "tls_1_3" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "tls_1_3"
  value      = "on"
}

resource "cloudflare_zone_setting" "min_tls_version" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "min_tls_version"
  value      = "1.2"
}

resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_zone_setting" "http3" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "http3"
  value      = "on"
}
