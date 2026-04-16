resource "aws_acm_certificate" "ssl" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}", "www.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.ssl.domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
    if dvo.domain_name != var.domain_name # exclude apex (already present in zone)
  }

  zone_id = var.cloudflare_zone_id
  name    = trimsuffix(each.value.name, ".")
  type    = each.value.type
  value   = each.value.value
  ttl     = 1
}

resource "cloudflare_record" "apex" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CNAME"
  value   = aws_cloudfront_distribution.webapp.domain_name
  ttl     = 1
  proxied = false
}

resource "cloudflare_record" "www" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  type    = "CNAME"
  value   = aws_cloudfront_distribution.webapp.domain_name
  ttl     = 1
  proxied = false
}

resource "cloudflare_zone_settings_override" "tls" {
  zone_id = var.cloudflare_zone_id

  settings {
    ssl              = "strict"
    tls_1_3          = "on"
    min_tls_version  = "1.2"
    always_use_https = "on"
    http3            = "on"
  }
}
