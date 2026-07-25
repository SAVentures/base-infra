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
