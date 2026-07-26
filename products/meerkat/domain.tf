# The apex (protoapp.xyz) CNAME to CloudFront is now owned by module.product
# (cloudflare_dns_record.app), which also carries www as an extra alias on
# the distribution. This record still points www's DNS at CloudFront.
resource "cloudflare_dns_record" "www_to_cloudfront" {
  zone_id = var.cloudflare_zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  content = module.product.cloudfront_domain_name
  ttl     = 1
  proxied = false
}
