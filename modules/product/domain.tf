resource "cloudflare_dns_record" "app" {
  count = var.manage_dns_record ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "CNAME"
  content = aws_cloudfront_distribution.webapp.domain_name
  ttl     = 1
  proxied = false
}
