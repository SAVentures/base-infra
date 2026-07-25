# Zone-level resources for the protoapp.xyz umbrella. Previously owned by
# products/protoapp, which is becoming an ordinary product (meerkat) and should
# not own shared infrastructure. Adopted via import blocks — the certificate is
# never reissued.

import {
  to = aws_acm_certificate.wildcard
  id = "arn:aws:acm:us-east-1:339713122183:certificate/c6fe1005-be4f-483c-be8d-b6cdef0881a1"
}

resource "aws_acm_certificate" "wildcard" {
  domain_name               = var.zone_domain
  subject_alternative_names = ["*.${var.zone_domain}", "www.${var.zone_domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  acm_validation_sans = toset(["*.${var.zone_domain}", "www.${var.zone_domain}"])
  acm_validation_by_domain = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      type    = dvo.resource_record_type
      content = dvo.resource_record_value
    }
  }
}

import {
  to = cloudflare_dns_record.acm_validation["*.protoapp.xyz"]
  id = "${var.cloudflare_zone_id}/ad46e76bab21935a06dd203a2264bba5"
}

import {
  to = cloudflare_dns_record.acm_validation["www.protoapp.xyz"]
  id = "${var.cloudflare_zone_id}/e002b4c74708d09c4f4d17ecc61843c5"
}

resource "cloudflare_dns_record" "acm_validation" {
  for_each = local.acm_validation_sans

  zone_id = var.cloudflare_zone_id
  name    = trimsuffix(local.acm_validation_by_domain[each.key].name, ".")
  type    = local.acm_validation_by_domain[each.key].type
  content = trimsuffix(local.acm_validation_by_domain[each.key].content, ".")
  ttl     = 1
}

# Zone settings are idempotent toggles, not stateful resources — they are
# redeclared here rather than imported. The product stack's copies are removed
# from its state in Step 6.
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
