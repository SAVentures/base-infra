resource "aws_acm_certificate" "ssl_cert" {
  domain_name               = "protoapp.xyz"
  validation_method         = "DNS"
  subject_alternative_names = ["*.protoapp.xyz", "www.protoapp.xyz"]

  lifecycle {
    create_before_destroy = true
  }
}


resource "cloudflare_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.ssl_cert.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      type    = dvo.resource_record_type
      value   = dvo.resource_record_value
      zone_id = var.cloudflare_zone_id
    } if dvo.domain_name != "protoapp.xyz" # Exclude apex domain
  }

  zone_id = each.value.zone_id
  name    = trimsuffix(each.value.name, ".")
  type    = each.value.type
  value   = each.value.value
  ttl     = 1 # Automatic TTL
}

resource "cloudflare_record" "root_to_cloudfront" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CNAME"
  value   = aws_cloudfront_distribution.webapp_distribution.domain_name
  ttl     = 1     # 1 means automatic
  proxied = false # CloudFront handles CDN/caching, so disable Cloudflare proxy
}

resource "cloudflare_record" "www_to_cloudfront" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  type    = "CNAME"
  value   = aws_cloudfront_distribution.webapp_distribution.domain_name
  ttl     = 1     # 1 means automatic
  proxied = false # CloudFront handles CDN/caching, so disable Cloudflare proxy
}

resource "cloudflare_zone_settings_override" "ssl_tls_settings" {
  zone_id = var.cloudflare_zone_id

  settings {
    ssl = "strict"
    # Use "full" if you have an SSL certificate on your origin (AWS ACM Certificate).
    # Use "strict" for SSL/TLS communication from Cloudflare to your origin server must be secure.
    tls_1_3          = "on"  # Enable TLS 1.3 for enhanced security.
    min_tls_version  = "1.2" # Minimum version of TLS to accept. Use "1.2" or "1.3".
    always_use_https = "on"  # Redirect all HTTP requests to HTTPS.
    http3            = "on"  # Optionally enable HTTP/3 for improved performance.
  }
}
