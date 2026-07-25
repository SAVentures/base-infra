# protoapp.xyz Subdomain Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `protoapp.xyz` into an umbrella zone hosting one prototype project per subdomain, with a shared Terraform module replacing per-product copy-paste, and both existing products migrated onto it.

**Architecture:** Zone-level resources (wildcard ACM cert, Cloudflare zone settings) and the three identical CloudFront policies move to `platform/`. A new `modules/product/` owns the *edge and routing* shape — S3, CloudFront, DNS, ALB target group, listener rule, manifest — and outputs a target group ARN that each product wires its own ECS service to. Compute stays per-product because env blocks are irreducibly product-specific.

**Tech Stack:** Terraform ≥1.5 (declarative `import`/`moved` blocks), AWS provider ~>5.0, Cloudflare provider ~>5.0, S3 remote state (one bucket per stack).

**Spec:** `docs/superpowers/specs/2026-07-25-protoapp-subdomain-hosting-design.md`

## Global Constraints

- **This is Terraform, not application code.** The TDD cycle maps to: write config → `terraform validate` → `terraform plan` and assert on the diff → apply → verify against AWS. The plan *is* the test.
- **Zero-diff gate:** `terraform plan -detailed-exitcode` exits `0` for no changes, `2` for changes present, `1` for error. Refactor tasks must exit `0`.
- **Never approve a plan showing `must be replaced`** on: `aws_s3_bucket`, `aws_cloudfront_distribution`, `aws_lb_target_group`, `aws_ecs_service`. It means a missing name override.
- **Region is `us-east-1`** for everything. CloudFront certs must live there.
- **Each product keeps its own state bucket.** `platform` → `protoapp-infra-terraform-state`, protoapp/meerkat → `protoapp-terraform-state`, sjocamp → `sjocamp-terraform-state`. Do not rename state buckets.
- **ALB rule priorities:** sjocamp `100`, meerkat `200`, new projects from `300` in steps of 10. Duplicates are rejected by AWS.
- **Never run `aws ssm put-parameter` by hand.** Secrets flow from gitignored `secrets.auto.tfvars` through Terraform (`products/*/secrets.tf:3-5`).
- **Commit after every task.** These are infrastructure changes; a clean history is the rollback mechanism.
- Personal prototype projects — brief downtime is acceptable. Do not add complexity to avoid it.

---

## File Structure

| Path | Responsibility |
|---|---|
| `platform/provider.tf` | + `cloudflare` provider block |
| `platform/main.tf` | + `cloudflare` in `required_providers` |
| `platform/zone.tf` | **new** — wildcard ACM cert, ACM validation records, Cloudflare zone settings |
| `platform/cloudfront-shared.tf` | **new** — shared cache policy, origin-request policy, SPA-routing function |
| `platform/outputs.tf` | + cert ARN, zone id, shared CloudFront resource ids |
| `platform/variables.tf` | + `cloudflare_zone_id`, `zone_domain` |
| `modules/product/variables.tf` | **new** — module inputs incl. all name overrides |
| `modules/product/cloudfront.tf` | **new** — S3 bucket, policy, OAC, distribution |
| `modules/product/alb-routing.tf` | **new** — target group + `X-Product-Id` listener rule |
| `modules/product/domain.tf` | **new** — Cloudflare CNAME for the subdomain |
| `modules/product/manifest.tf` | **new** — SSM `/{product}/manifest` |
| `modules/product/outputs.tf` | **new** — target group ARN, distribution id, bucket id |
| `products/sjocamp/main.tf` | + module call + `moved` blocks |
| `products/meerkat/` | renamed from `products/protoapp/` |

---

## Task 1: Fix the ALB catch-all

Standalone defect fix, independent of everything else. `products/protoapp/alb-routing.tf:22-36` matches `/api/*` with **no header condition**, so any project that misconfigures `X-Product-Id` reaches protoapp's API and database.

**Files:**
- Modify: `products/protoapp/s3-cloudfront.tf:94-104` (add `custom_header` to ALB origin)
- Modify: `products/protoapp/alb-routing.tf:22-36` (add header condition, change priority)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: protoapp's CloudFront now sends `X-Product-Id: protoapp`. Task 8 renames that value to `meerkat`.

- [ ] **Step 1: Add the header to protoapp's ALB origin**

In `products/protoapp/s3-cloudfront.tf`, inside the `origin` block with `origin_id = "ALB-API"`, after the `custom_origin_config` block:

```hcl
    custom_header {
      name  = "X-Product-Id"
      value = var.product
    }
```

- [ ] **Step 2: Add the header condition to the listener rule**

Replace the comment and resource at `products/protoapp/alb-routing.tf:18-36` with:

```hcl
# Routes /api/* carrying X-Product-Id=protoapp (injected by this product's
# CloudFront) to protoapp's target group. Previously this rule was header-less
# at priority 1000 and acted as a catch-all, silently absorbing any misrouted
# /api/* traffic. The listener's 404 default is now the only fallback.
resource "aws_lb_listener_rule" "alb_listener_rule_api_http" {
  listener_arn = data.terraform_remote_state.platform.outputs.alb_listener_http_arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.ecs_target.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  condition {
    http_header {
      http_header_name = "X-Product-Id"
      values           = [var.product]
    }
  }
}
```

- [ ] **Step 3: Validate and review the plan**

```bash
terraform -chdir=products/protoapp init -upgrade
terraform -chdir=products/protoapp validate
terraform -chdir=products/protoapp plan
```

Expected: exactly two changes — the distribution updated in place (new `custom_header`), and the listener rule updated in place (new condition + priority). **`aws_cloudfront_distribution` must say `will be updated in-place`, never `must be replaced`.**

- [ ] **Step 4: Apply**

```bash
terraform -chdir=products/protoapp apply
```

CloudFront propagation takes ~5-15 minutes. Wait for `Deployed`:

```bash
aws cloudfront get-distribution --id "$(terraform -chdir=products/protoapp output -raw cloudfront_distribution_id)" \
  --query 'Distribution.Status' --output text
```

- [ ] **Step 5: Verify the app still works and the catch-all is closed**

```bash
# Real traffic still routes:
curl -s -o /dev/null -w '%{http_code}\n' https://protoapp.xyz/api/health   # expect 200

# Direct ALB hit without the header now 404s instead of reaching protoapp:
ALB=$(terraform -chdir=platform output -raw alb_dns_name)
curl -s -o /dev/null -w '%{http_code}\n' "http://$ALB/api/health"          # expect 404
```

- [ ] **Step 6: Commit**

```bash
git add products/protoapp/alb-routing.tf products/protoapp/s3-cloudfront.tf
git commit -m "fix(alb): close protoapp header-less /api/* catch-all

The rule matched /api/* with no header condition at priority 1000, so any
product missing its X-Product-Id header reached protoapp's API and database.
Now requires X-Product-Id=protoapp at priority 200; the listener's 404 default
is the only fallback."
```

---

## Task 2: Hoist zone resources to platform

**Files:**
- Modify: `platform/main.tf` (add cloudflare to `required_providers`)
- Modify: `platform/provider.tf` (add provider block)
- Modify: `platform/variables.tf` (add zone vars)
- Create: `platform/zone.tf`
- Modify: `platform/outputs.tf`
- Modify: `products/protoapp/domain.tf` (remove hoisted resources)

**Interfaces:**
- Consumes: nothing.
- Produces: `platform` outputs `acm_certificate_arn` (string), `cloudflare_zone_id` (string), `zone_domain` (string). Tasks 5-10 consume these.

- [ ] **Step 1: Capture the existing cert ARN and DNS record IDs**

These are needed verbatim for the import blocks. Run and keep the output:

```bash
terraform -chdir=products/protoapp state show aws_acm_certificate.ssl_cert | grep -E '^\s+(arn|id)\s+='
terraform -chdir=products/protoapp state show 'cloudflare_dns_record.acm_validation["*.protoapp.xyz"]' | grep -E '^\s+id\s+='
terraform -chdir=products/protoapp state show 'cloudflare_dns_record.acm_validation["www.protoapp.xyz"]' | grep -E '^\s+id\s+='
```

- [ ] **Step 2: Add the cloudflare provider to platform**

In `platform/main.tf`, inside `required_providers`:

```hcl
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
```

In `platform/provider.tf`, append — this must match `products/protoapp/provider.tf` exactly, which authenticates with the Cloudflare *global API key* pulled from SSM plus an account email, **not** an API token from the environment:

```hcl
data "aws_ssm_parameter" "cloudflare_api_key" {
  name = "/cloudflare/api_key"
}

provider "cloudflare" {
  email   = var.cloudflare_email
  api_key = data.aws_ssm_parameter.cloudflare_api_key.value
}
```

In `platform/variables.tf`, append:

```hcl
variable "cloudflare_email" {
  description = "Cloudflare account email (paired with the global API key from /cloudflare/api_key)"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the umbrella zone (protoapp.xyz)"
  type        = string
  default     = "e1fcf5e6c9b60043f75049228a8e3088"
}

variable "zone_domain" {
  description = "Umbrella domain hosting all product subdomains"
  type        = string
  default     = "protoapp.xyz"
}
```

- [ ] **Step 3: Create platform/zone.tf**

Substitute the ARN and record IDs captured in Step 1 into the `import` blocks.

```hcl
# Zone-level resources for the protoapp.xyz umbrella. Previously owned by
# products/protoapp, which is becoming an ordinary product (meerkat) and should
# not own shared infrastructure. Adopted via import blocks — the certificate is
# never reissued.

import {
  to = aws_acm_certificate.wildcard
  id = "REPLACE_WITH_CERT_ARN_FROM_STEP_1"
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
  id = "${var.cloudflare_zone_id}/REPLACE_WITH_WILDCARD_RECORD_ID"
}

import {
  to = cloudflare_dns_record.acm_validation["www.protoapp.xyz"]
  id = "${var.cloudflare_zone_id}/REPLACE_WITH_WWW_RECORD_ID"
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
```

- [ ] **Step 4: Add platform outputs**

Append to `platform/outputs.tf`:

```hcl
output "acm_certificate_arn" {
  value       = aws_acm_certificate.wildcard.arn
  description = "Wildcard cert covering protoapp.xyz and *.protoapp.xyz; used by every product CloudFront"
}

output "cloudflare_zone_id" {
  value       = var.cloudflare_zone_id
  description = "Cloudflare zone ID for the umbrella zone"
}

output "zone_domain" {
  value       = var.zone_domain
  description = "Umbrella domain hosting all product subdomains"
}
```

- [ ] **Step 5: Plan and verify the imports are adoptions, not creations**

```bash
terraform -chdir=platform init -upgrade
terraform -chdir=platform validate
terraform -chdir=platform plan
```

Expected: three resources show `will be imported`, five `cloudflare_zone_setting` show `will be created`. **No resource may show `will be destroyed` or `must be replaced`.** If the ACM cert shows as created rather than imported, the ARN in Step 3 is wrong — stop and fix it.

- [ ] **Step 6: Apply platform, then release the product's claim**

```bash
terraform -chdir=platform apply
```

Now remove the duplicated blocks from `products/protoapp/domain.tf`: delete `aws_acm_certificate.ssl_cert` (lines 1-9), the `locals` block (11-20), `cloudflare_dns_record.acm_validation` (22-30), and all five `cloudflare_zone_setting` resources (51-79). Keep `root_to_cloudfront` and `www_to_cloudfront`.

Point the distribution at the platform cert. In `products/protoapp/s3-cloudfront.tf:150`:

```hcl
    acm_certificate_arn      = data.terraform_remote_state.platform.outputs.acm_certificate_arn
```

Drop the orphaned state entries (this deletes nothing in AWS — platform owns them now):

```bash
cd products/protoapp
terraform state rm aws_acm_certificate.ssl_cert
terraform state rm 'cloudflare_dns_record.acm_validation["*.protoapp.xyz"]'
terraform state rm 'cloudflare_dns_record.acm_validation["www.protoapp.xyz"]'
for s in ssl tls_1_3 min_tls_version always_use_https http3; do
  terraform state rm "cloudflare_zone_setting.$s"
done
cd ../..
```

- [ ] **Step 7: Confirm the product stack is clean**

```bash
terraform -chdir=products/protoapp plan -detailed-exitcode; echo "exit=$?"
```

Expected: `exit=0`. The cert ARN is unchanged (same certificate, now sourced from remote state), so the distribution should show no diff. If it shows an update to `viewer_certificate`, the ARNs differ — investigate before applying.

- [ ] **Step 8: Commit**

```bash
git add platform/ products/protoapp/domain.tf products/protoapp/s3-cloudfront.tf
git commit -m "refactor(platform): own the protoapp.xyz zone cert and settings

The wildcard cert and Cloudflare zone settings lived in products/protoapp,
which is becoming an ordinary product. Adopted into platform via import blocks
so the cert is never reissued; products now consume it from remote state."
```

---

## Task 3: Shared CloudFront resources in platform

The cache policy, origin-request policy and SPA-routing function are byte-identical between the two products and are account-level reusable resources.

**Files:**
- Create: `platform/cloudfront-shared.tf`
- Modify: `platform/outputs.tf`

**Interfaces:**
- Consumes: nothing.
- Produces: outputs `cloudfront_api_cache_policy_id`, `cloudfront_api_origin_request_policy_id`, `cloudfront_spa_function_arn` (all strings). Task 4 consumes them.

- [ ] **Step 1: Create platform/cloudfront-shared.tf**

Bodies copied verbatim from `products/sjocamp/s3-cloudfront.tf` so repointing in Task 4 is a no-op in behaviour.

```hcl
# CloudFront policies and functions are account-level reusable resources, and
# were byte-identical across both products. Defined once here; products
# reference them by id. This also removes the name-collision class that made
# products/protoapp impossible to clone.

resource "aws_cloudfront_function" "spa_routing" {
  name    = "shared-spa-routing"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite non-asset, non-API requests to index.html for SPA routing"
  publish = true
  code    = <<-EOT
function handler(event) {
    var request = event.request;
    var uri = request.uri;

    // Don't rewrite API requests
    if (uri.startsWith('/api/')) {
        return request;
    }

    // Static assets (anything with an extension) pass through untouched
    if (uri.includes('.')) {
        return request;
    }

    // Client-side routes rewrite to index.html; the browser URL is unchanged
    request.uri = '/index.html';

    return request;
}
EOT
}

resource "aws_cloudfront_cache_policy" "api_no_cache" {
  name        = "shared-api-no-cache"
  comment     = "No caching for API requests"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_origin_request_policy" "api_origin_request" {
  name    = "shared-api-origin-request"
  comment = "Forward viewer headers, cookies and query strings to the API origin"

  cookies_config {
    cookie_behavior = "all"
  }

  headers_config {
    header_behavior = "allViewerAndWhitelistCloudFront"
    headers {
      items = [
        "CloudFront-Viewer-Address",
        "CloudFront-Viewer-Country",
        "CloudFront-Viewer-Country-Region",
        "CloudFront-Viewer-City",
        "CloudFront-Viewer-Postal-Code",
        "CloudFront-Viewer-Metro-Code",
        "CloudFront-Viewer-Time-Zone",
        "CloudFront-Viewer-Latitude",
        "CloudFront-Viewer-Longitude",
        "CloudFront-Is-Mobile-Viewer",
      ]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}
```

- [ ] **Step 2: Add outputs**

Append to `platform/outputs.tf`:

```hcl
output "cloudfront_api_cache_policy_id" {
  value       = aws_cloudfront_cache_policy.api_no_cache.id
  description = "Shared no-cache policy for /api/* behaviours"
}

output "cloudfront_api_origin_request_policy_id" {
  value       = aws_cloudfront_origin_request_policy.api_origin_request.id
  description = "Shared origin-request policy forwarding viewer headers to the API"
}

output "cloudfront_spa_function_arn" {
  value       = aws_cloudfront_function.spa_routing.arn
  description = "Shared viewer-request function rewriting SPA routes to index.html"
}
```

- [ ] **Step 3: Plan — expect three additions only**

```bash
terraform -chdir=platform validate
terraform -chdir=platform plan
```

Expected: exactly 3 to add, 0 to change, 0 to destroy. The new names (`shared-*`) cannot collide with the existing per-product names.

- [ ] **Step 4: Apply and commit**

```bash
terraform -chdir=platform apply
git add platform/cloudfront-shared.tf platform/outputs.tf
git commit -m "feat(platform): add shared CloudFront policies and SPA function

These were byte-identical across both products. Defining them once removes the
duplication and the account-global name collisions that blocked cloning."
```

---

## Task 4: Repoint products at the shared CloudFront resources

Ordering matters: a policy cannot be deleted while a distribution still references it.

**Files:**
- Modify: `products/protoapp/s3-cloudfront.tf` (repoint, then delete local resources)
- Modify: `products/sjocamp/s3-cloudfront.tf` (same)

**Interfaces:**
- Consumes: `platform` outputs from Task 3.
- Produces: neither product defines CloudFront policies or functions any more.

- [ ] **Step 1: Repoint protoapp**

In `products/protoapp/s3-cloudfront.tf`, replace the three references:

```hcl
    # in default_cache_behavior.function_association
    function_arn = data.terraform_remote_state.platform.outputs.cloudfront_spa_function_arn

    # in the /api/* ordered_cache_behavior
    cache_policy_id          = data.terraform_remote_state.platform.outputs.cloudfront_api_cache_policy_id
    origin_request_policy_id = data.terraform_remote_state.platform.outputs.cloudfront_api_origin_request_policy_id
```

- [ ] **Step 2: Repoint sjocamp**

Make the identical three substitutions in `products/sjocamp/s3-cloudfront.tf`.

- [ ] **Step 3: Plan both — in-place updates only**

```bash
terraform -chdir=products/protoapp plan
terraform -chdir=products/sjocamp plan
```

Expected per stack: the distribution `will be updated in-place`. The old policies/functions still exist and are still in state — they are **not** removed yet. **A distribution showing `must be replaced` is a stop condition.**

- [ ] **Step 4: Apply both and wait for propagation**

```bash
terraform -chdir=products/protoapp apply
terraform -chdir=products/sjocamp apply
```

Wait for both distributions to reach `Deployed` before continuing — deleting a policy still attached to an in-progress deployment fails.

```bash
for p in protoapp sjocamp; do
  id=$(terraform -chdir=products/$p output -raw cloudfront_distribution_id)
  echo "$p: $(aws cloudfront get-distribution --id "$id" --query 'Distribution.Status' --output text)"
done
```

- [ ] **Step 5: Verify both sites still serve**

```bash
curl -s -o /dev/null -w 'protoapp %{http_code}\n' https://protoapp.xyz/
curl -s -o /dev/null -w 'protoapp api %{http_code}\n' https://protoapp.xyz/api/health
curl -s -o /dev/null -w 'sjocamp %{http_code}\n' https://app.sjocamp.co/
curl -s -o /dev/null -w 'sjocamp api %{http_code}\n' https://app.sjocamp.co/api/health
```

All four must return 200. A deep-link check confirms the shared SPA function works:

```bash
curl -s -o /dev/null -w 'spa route %{http_code}\n' https://protoapp.xyz/some/client/route
```

- [ ] **Step 6: Delete the now-unreferenced per-product resources**

Remove from `products/protoapp/s3-cloudfront.tf`: `aws_cloudfront_function.spa_routing` (51-79), `aws_cloudfront_cache_policy.api_cache_policy` (161-179), `aws_cloudfront_origin_request_policy.api_origin_request_policy` (181-210).

Remove the equivalent three resources from `products/sjocamp/s3-cloudfront.tf`.

```bash
terraform -chdir=products/protoapp apply
terraform -chdir=products/sjocamp apply
```

Expected: 3 destroyed per stack, nothing else.

- [ ] **Step 7: Commit**

```bash
git add products/protoapp/s3-cloudfront.tf products/sjocamp/s3-cloudfront.tf
git commit -m "refactor(cloudfront): use shared platform policies and SPA function

Both products referenced byte-identical copies. Repointed at the platform
resources, then removed the per-product duplicates."
```

---

## Task 5: Create modules/product

The module owns edge and routing only. Compute stays per-product — see the spec's "Target architecture" for why.

**Files:**
- Create: `modules/product/versions.tf`, `variables.tf`, `cloudfront.tf`, `alb-routing.tf`, `domain.tf`, `manifest.tf`, `outputs.tf`

**Interfaces:**
- Consumes: platform outputs from Tasks 2-3, passed in as variables.
- Produces: `module.product.target_group_arn`, `.cloudfront_distribution_id`, `.cloudfront_domain_name`, `.webapp_bucket_id`. Tasks 6-7 consume these.

- [ ] **Step 1: Write modules/product/versions.tf**

A child module resolves provider source addresses from **its own** `required_providers` block, not the root's. Without `cloudflare` declared here, Terraform assumes `hashicorp/cloudflare` and `init` fails — both standalone and in every root stack that consumes the module, regardless of what the root declares.

```hcl
terraform {
  required_version = ">= 1.2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}
```

No `provider` configuration blocks and no `backend` in the module — those stay in the root stacks, which pass configured providers down.

- [ ] **Step 2: Write modules/product/variables.tf**

```hcl
variable "product" {
  description = "Product slug — used in resource names, SSM paths and the X-Product-Id routing header"
  type        = string
}

variable "display_name" {
  description = "Human-facing product name, surfaced in the SSM manifest"
  type        = string
}

variable "domain" {
  description = "Fully-qualified domain this product serves. A pure input: nothing derives a hostname from any other source, so moving a product to its own apex is a one-line change."
  type        = string
}

variable "aws_region" {
  description = "AWS region (must match platform)"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment tag applied to product resources"
  type        = string
  default     = "production"
}

# --- Platform wiring ---

variable "platform_alb_dns_name" {
  type        = string
  description = "Shared ALB DNS name, used as the API origin"
}

variable "platform_alb_listener_arn" {
  type        = string
  description = "Shared HTTP listener ARN to attach this product's rule to"
}

variable "platform_vpc_id" {
  type        = string
  description = "Shared VPC ID for the target group"
}

variable "platform_acm_certificate_arn" {
  type        = string
  description = "Wildcard cert covering this product's domain"
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone holding this product's DNS record"
}

variable "cloudfront_cache_policy_id" {
  type        = string
  description = "Shared no-cache policy for /api/*"
}

variable "cloudfront_origin_request_policy_id" {
  type        = string
  description = "Shared origin-request policy for /api/*"
}

variable "cloudfront_spa_function_arn" {
  type        = string
  description = "Shared viewer-request function for SPA routing"
}

# --- Routing ---

variable "alb_rule_priority" {
  description = "ALB listener rule priority. sjocamp 100, meerkat 200, new projects from 300 in steps of 10. AWS rejects duplicates."
  type        = number
}

variable "extra_aliases" {
  description = "Additional CloudFront aliases beyond var.domain. Used during a domain move to serve old and new names simultaneously."
  type        = list(string)
  default     = []
}

variable "manage_dns_record" {
  description = "Whether this module manages the Cloudflare CNAME. False when the record lives in a zone this stack does not own."
  type        = bool
  default     = true
}

# --- Name overrides ---
# Every attribute below forces resource replacement when changed. Existing
# products pass their live names so migration produces a zero-change plan;
# new projects omit them and get the conventional default.

variable "s3_bucket_name" {
  description = "Override the webapp bucket name. Bucket names are cosmetic and need not match the serving domain."
  type        = string
  default     = null
}

variable "target_group_name" {
  description = "Override the ALB target group name"
  type        = string
  default     = null
}

variable "oac_name" {
  description = "Override the CloudFront origin access control name"
  type        = string
  default     = null
}

variable "log_group_name" {
  description = "Override the CloudFront log group name"
  type        = string
  default     = null
}

locals {
  s3_bucket_name    = coalesce(var.s3_bucket_name, "protoapp-${var.product}-webapp")
  target_group_name = coalesce(var.target_group_name, "${var.product}-api-tg")
  oac_name          = coalesce(var.oac_name, "${var.product}-webapp-oac")
  log_group_name    = coalesce(var.log_group_name, "/aws/cloudfront/${var.product}-webapp")
  cloudfront_aliases = concat([var.domain], var.extra_aliases)
}
```

- [ ] **Step 2: Write modules/product/cloudfront.tf**

```hcl
resource "aws_s3_bucket" "webapp" {
  bucket = local.s3_bucket_name

  tags = {
    Name        = "${var.product} webapp static hosting"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "webapp" {
  bucket = aws_s3_bucket.webapp.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "webapp" {
  bucket = aws_s3_bucket.webapp.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.webapp.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.webapp.arn
          }
        }
      }
    ]
  })
}

resource "aws_cloudfront_origin_access_control" "webapp" {
  name                              = local.oac_name
  description                       = "Origin access control for ${var.product} webapp bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "webapp" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = local.cloudfront_aliases

  origin {
    domain_name              = aws_s3_bucket.webapp.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.webapp.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.webapp.id
  }

  origin {
    domain_name = var.platform_alb_dns_name
    origin_id   = "ALB-API"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Routes this product's API traffic to its own target group on the shared
    # ALB. Without it the request falls through to the listener's 404 default.
    custom_header {
      name  = "X-Product-Id"
      value = var.product
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.webapp.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = var.cloudfront_spa_function_arn
    }
  }

  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB-API"

    cache_policy_id          = var.cloudfront_cache_policy_id
    origin_request_policy_id = var.cloudfront_origin_request_policy_id

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.platform_acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name        = "${var.product} webapp distribution"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "cloudfront" {
  name              = local.log_group_name
  retention_in_days = 7

  tags = {
    Name        = "${var.product} CloudFront logs"
    Environment = var.environment
  }
}
```

- [ ] **Step 3: Write modules/product/alb-routing.tf**

```hcl
resource "aws_lb_target_group" "api" {
  name        = local.target_group_name
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.platform_vpc_id
  target_type = "instance"

  health_check {
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    interval            = 30
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Matches X-Product-Id rather than host_header deliberately: header values
# survive a domain change, host rules would need editing every time a product
# moves to its own apex — a planned event.
resource "aws_lb_listener_rule" "api" {
  listener_arn = var.platform_alb_listener_arn
  priority     = var.alb_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  condition {
    http_header {
      http_header_name = "X-Product-Id"
      values           = [var.product]
    }
  }
}
```

- [ ] **Step 4: Write modules/product/domain.tf**

```hcl
resource "cloudflare_dns_record" "app" {
  count = var.manage_dns_record ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "CNAME"
  content = aws_cloudfront_distribution.webapp.domain_name
  ttl     = 1
  proxied = false
}
```

`proxied = false` is required: CloudFront terminates TLS with the ACM cert, and the zone's SSL mode is `strict`.

- [ ] **Step 5: Write modules/product/manifest.tf and outputs.tf**

`manifest.tf`:

```hcl
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
```

`outputs.tf`:

```hcl
output "target_group_arn" {
  value       = aws_lb_target_group.api.arn
  description = "Attach the product's ECS service to this"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.webapp.id
  description = "For cache invalidation in CI"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.webapp.domain_name
  description = "Distribution hostname, for DNS records managed outside this module"
}

output "webapp_bucket_id" {
  value       = aws_s3_bucket.webapp.id
  description = "Sync built static assets here"
}

output "listener_rule_arn" {
  value       = aws_lb_listener_rule.api.arn
  description = "For ECS services that must depend_on the rule existing"
}
```

- [ ] **Step 6: Validate the module in isolation**

```bash
terraform -chdir=modules/product init -backend=false
terraform -chdir=modules/product validate
terraform fmt -check -recursive modules/
```

Expected: `Success! The configuration is valid.` No apply — the module has no backend and no consumer yet.

- [ ] **Step 7: Commit**

```bash
git add modules/product/
git commit -m "feat(modules): add reusable product module for edge and routing

Owns S3, CloudFront, DNS, ALB target group, listener rule and manifest.
Compute stays per-product: the ECS environment block is irreducibly
product-specific. Name overrides let existing products migrate with a
zero-change plan."
```

---

## Task 6: Migrate sjocamp onto the module

sjocamp first — it is the template the module was extracted from, so its diff is the most predictable.

**Files:**
- Modify: `products/sjocamp/main.tf` (module call + `moved` blocks)
- Delete: `products/sjocamp/s3-cloudfront.tf`, `alb-routing.tf`, `manifest.tf`
- Modify: `products/sjocamp/domain.tf`, `ecs-service.tf`, `outputs.tf`

**Interfaces:**
- Consumes: `modules/product` from Task 5.
- Produces: proves the module reproduces live infrastructure exactly. Task 7 depends on this confidence.

- [ ] **Step 1: Add the module call**

Append to `products/sjocamp/main.tf`:

```hcl
module "product" {
  source = "../../modules/product"

  product      = var.product
  display_name = var.display_name
  domain       = var.domain_name
  aws_region   = var.aws_region
  environment  = var.environment

  platform_alb_dns_name        = data.terraform_remote_state.platform.outputs.alb_dns_name
  platform_alb_listener_arn    = data.terraform_remote_state.platform.outputs.alb_listener_http_arn
  platform_vpc_id              = data.terraform_remote_state.platform.outputs.vpc_id
  platform_acm_certificate_arn = aws_acm_certificate.ssl_cert.arn

  cloudflare_zone_id                  = var.cloudflare_zone_id
  cloudfront_cache_policy_id          = data.terraform_remote_state.platform.outputs.cloudfront_api_cache_policy_id
  cloudfront_origin_request_policy_id = data.terraform_remote_state.platform.outputs.cloudfront_api_origin_request_policy_id
  cloudfront_spa_function_arn         = data.terraform_remote_state.platform.outputs.cloudfront_spa_function_arn

  alb_rule_priority = var.alb_rule_priority

  # Live names — omitting any of these replaces the resource.
  s3_bucket_name    = "app.sjocamp.co-webapp"
  target_group_name = "sjocamp-api-tg"
  oac_name          = "sjocamp-webapp-oac"
  log_group_name    = "/aws/cloudfront/sjocamp-webapp"
}
```

sjocamp keeps its own cert until Task 10 — it is still serving `app.sjocamp.co` in the `sjocamp.co` zone, which the platform wildcard does not cover.

- [ ] **Step 2: Add the moved blocks**

Append to `products/sjocamp/main.tf`. These are pure state-address changes within one state file — no `terraform state mv` anywhere.

```hcl
moved {
  from = aws_s3_bucket.webapp_bucket
  to   = module.product.aws_s3_bucket.webapp
}

moved {
  from = aws_s3_bucket_public_access_block.webapp_bucket_public_access
  to   = module.product.aws_s3_bucket_public_access_block.webapp
}

moved {
  from = aws_s3_bucket_policy.webapp_bucket_policy
  to   = module.product.aws_s3_bucket_policy.webapp
}

moved {
  from = aws_cloudfront_origin_access_control.webapp_oac
  to   = module.product.aws_cloudfront_origin_access_control.webapp
}

moved {
  from = aws_cloudfront_distribution.webapp_distribution
  to   = module.product.aws_cloudfront_distribution.webapp
}

moved {
  from = aws_cloudwatch_log_group.cloudfront_logs
  to   = module.product.aws_cloudwatch_log_group.cloudfront
}

moved {
  from = aws_lb_target_group.api
  to   = module.product.aws_lb_target_group.api
}

moved {
  from = aws_lb_listener_rule.api
  to   = module.product.aws_lb_listener_rule.api
}

moved {
  from = cloudflare_dns_record.app_to_cloudfront
  to   = module.product.cloudflare_dns_record.app[0]
}

moved {
  from = aws_ssm_parameter.manifest
  to   = module.product.aws_ssm_parameter.manifest
}
```

The `[0]` index on the DNS record is required — `manage_dns_record` makes it a counted resource.

- [ ] **Step 3: Delete the superseded files and fix references**

```bash
git rm products/sjocamp/s3-cloudfront.tf products/sjocamp/alb-routing.tf products/sjocamp/manifest.tf
```

In `products/sjocamp/domain.tf`, delete `cloudflare_dns_record.app_to_cloudfront` (the module owns it now). Keep the cert and its validation record.

In `products/sjocamp/ecs-service.tf`, repoint the service to the module's target group:

```hcl
  load_balancer {
    container_name   = var.container_name_api
    container_port   = 80
    target_group_arn = module.product.target_group_arn
  }

  depends_on = [module.product]
```

In `products/sjocamp/outputs.tf`, repoint every reference — for example:

```hcl
output "cloudfront_domain_name" {
  value = module.product.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  value = module.product.cloudfront_distribution_id
}

output "api_target_group_arn" {
  value = module.product.target_group_arn
}
```

- [ ] **Step 4: The zero-diff gate**

```bash
terraform -chdir=products/sjocamp init
terraform -chdir=products/sjocamp validate
terraform -chdir=products/sjocamp plan -detailed-exitcode; echo "exit=$?"
```

**Expected: `exit=0`.** Terraform prints the `moved` block resolutions and then `No changes.`

If `exit=2`, read the diff before doing anything else:
- `must be replaced` on the bucket, distribution or target group → a name override is wrong. Fix the input in Step 1. **Never approve it.**
- `~ update in-place` on tags or descriptions → the module's cosmetic strings differ from the original. Either align the module text or accept it, but confirm the change is genuinely cosmetic first.

- [ ] **Step 5: Apply and verify**

Even at `exit=0`, apply so the state records the moves:

```bash
terraform -chdir=products/sjocamp apply
curl -s -o /dev/null -w 'sjocamp %{http_code}\n' https://app.sjocamp.co/
curl -s -o /dev/null -w 'sjocamp api %{http_code}\n' https://app.sjocamp.co/api/health
```

Both must return 200.

- [ ] **Step 6: Commit**

```bash
git add products/sjocamp/
git commit -m "refactor(sjocamp): migrate onto modules/product

Pure state-address change via moved blocks — terraform plan reports No changes.
Live resource names passed as overrides so nothing is replaced."
```

---

## Task 7: Migrate protoapp onto the module

Same mechanism as Task 6, but protoapp is the legacy stack with six hardcoded names, so every override matters.

**Files:**
- Modify: `products/protoapp/main.tf`
- Delete: `products/protoapp/s3-cloudfront.tf`, `alb-routing.tf`, `manifest.tf`
- Modify: `products/protoapp/domain.tf`, `ecs-service.tf`, `capture-worker.tf`, `outputs.tf`

**Interfaces:**
- Consumes: `modules/product` from Task 5.
- Produces: both products on one pattern. Task 8 renames this stack.

- [ ] **Step 1: Add the module call with legacy name overrides**

Append to `products/protoapp/main.tf`:

```hcl
module "product" {
  source = "../../modules/product"

  product      = var.product
  display_name = var.display_name
  domain       = var.domain_name
  aws_region   = var.aws_region
  environment  = var.environment

  platform_alb_dns_name        = data.terraform_remote_state.platform.outputs.alb_dns_name
  platform_alb_listener_arn    = data.terraform_remote_state.platform.outputs.alb_listener_http_arn
  platform_vpc_id              = data.terraform_remote_state.platform.outputs.vpc_id
  platform_acm_certificate_arn = data.terraform_remote_state.platform.outputs.acm_certificate_arn

  cloudflare_zone_id                  = var.cloudflare_zone_id
  cloudfront_cache_policy_id          = data.terraform_remote_state.platform.outputs.cloudfront_api_cache_policy_id
  cloudfront_origin_request_policy_id = data.terraform_remote_state.platform.outputs.cloudfront_api_origin_request_policy_id
  cloudfront_spa_function_arn         = data.terraform_remote_state.platform.outputs.cloudfront_spa_function_arn

  alb_rule_priority = 200

  # protoapp currently serves the apex plus www.
  extra_aliases = ["www.${var.domain_name}"]

  # Legacy hardcoded names. Every one of these forces replacement if omitted:
  # the bucket would be destroyed and recreated empty, the distribution would
  # take ~20 minutes to rebuild.
  s3_bucket_name    = "protoapp.xyz-webapp"
  target_group_name = "ecs-target-group"
  oac_name          = "webapp-oac"
  log_group_name    = "/aws/cloudfront/webapp"
}
```

- [ ] **Step 2: Add the moved blocks**

Note the differing source names — protoapp's legacy identifiers are not sjocamp's.

```hcl
moved {
  from = aws_s3_bucket.webapp_bucket
  to   = module.product.aws_s3_bucket.webapp
}

moved {
  from = aws_s3_bucket_public_access_block.webapp_bucket_public_access
  to   = module.product.aws_s3_bucket_public_access_block.webapp
}

moved {
  from = aws_s3_bucket_policy.webapp_bucket_policy
  to   = module.product.aws_s3_bucket_policy.webapp
}

moved {
  from = aws_cloudfront_origin_access_control.webapp_oac
  to   = module.product.aws_cloudfront_origin_access_control.webapp
}

moved {
  from = aws_cloudfront_distribution.webapp_distribution
  to   = module.product.aws_cloudfront_distribution.webapp
}

moved {
  from = aws_cloudwatch_log_group.cloudfront_logs
  to   = module.product.aws_cloudwatch_log_group.cloudfront
}

# Legacy name: aws_alb_target_group, not aws_lb_target_group.
moved {
  from = aws_alb_target_group.ecs_target
  to   = module.product.aws_lb_target_group.api
}

moved {
  from = aws_lb_listener_rule.alb_listener_rule_api_http
  to   = module.product.aws_lb_listener_rule.api
}

moved {
  from = cloudflare_dns_record.root_to_cloudfront
  to   = module.product.cloudflare_dns_record.app[0]
}

moved {
  from = aws_ssm_parameter.manifest
  to   = module.product.aws_ssm_parameter.manifest
}
```

`aws_alb_target_group` and `aws_lb_target_group` are aliases for the same AWS API resource, so this move is valid.

`cloudflare_dns_record.www_to_cloudfront` stays in the product stack — the module manages exactly one record, and www is an extra alias.

- [ ] **Step 3: Delete superseded files and fix references**

```bash
git rm products/protoapp/s3-cloudfront.tf products/protoapp/alb-routing.tf products/protoapp/manifest.tf
```

In `products/protoapp/domain.tf`, delete `cloudflare_dns_record.root_to_cloudfront`. Keep `www_to_cloudfront` but repoint it:

```hcl
resource "cloudflare_dns_record" "www_to_cloudfront" {
  zone_id = var.cloudflare_zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  content = module.product.cloudfront_domain_name
  ttl     = 1
  proxied = false
}
```

In `products/protoapp/ecs-service.tf`, repoint the `load_balancer` block and `depends_on` to `module.product.target_group_arn` and `module.product` exactly as in Task 6 Step 3.

`products/protoapp/capture-worker.tf` needs no change — the capture worker has no load balancer attachment.

Repoint `products/protoapp/outputs.tf` at the module outputs.

- [ ] **Step 4: The zero-diff gate**

```bash
terraform -chdir=products/protoapp init
terraform -chdir=products/protoapp validate
terraform -chdir=products/protoapp plan -detailed-exitcode; echo "exit=$?"
```

**Expected: `exit=0`.**

The single most dangerous failure here is `aws_s3_bucket.webapp must be replaced` — that destroys the live webapp bucket. If you see it, `s3_bucket_name` in Step 1 is wrong. The assets are rebuildable from CI, but do not find that out by accident.

- [ ] **Step 5: Apply and verify**

```bash
terraform -chdir=products/protoapp apply
curl -s -o /dev/null -w 'apex %{http_code}\n' https://protoapp.xyz/
curl -s -o /dev/null -w 'www %{http_code}\n' https://www.protoapp.xyz/
curl -s -o /dev/null -w 'api %{http_code}\n' https://protoapp.xyz/api/health
```

All three must return 200.

- [ ] **Step 6: Commit**

```bash
git add products/protoapp/
git commit -m "refactor(protoapp): migrate onto modules/product

Legacy hardcoded names (protoapp.xyz-webapp, ecs-target-group, webapp-oac,
/aws/cloudfront/webapp) passed as overrides so the plan is zero-diff. Both
products now share one pattern."
```

---

## Task 8: Rename protoapp to meerkat

Directory, slug, 29 SSM paths and the ECR repository, in one pass.

**Files:**
- Rename: `products/protoapp/` → `products/meerkat/`
- Modify: `products/meerkat/variables.tf`, `secrets.tf`, `data.tf`

**Interfaces:**
- Consumes: Task 7's migrated stack.
- Produces: `X-Product-Id: meerkat`, SSM prefix `/meerkat/*`. The app repo must be cut over between Steps 5 and 7.

- [ ] **Step 1: Precondition — verify every secret value is present**

**Do not skip this.** The eight parameters adopted via `import` at `products/protoapp/secrets.tf:13-44` are re-created under new paths. If a value is missing from `secrets.auto.tfvars`, Terraform cannot write it — and a regenerated `jwt_secret` invalidates every logged-in session.

```bash
cd products/protoapp
for v in jwt_secret google_client_id google_client_secret stripe_webhook_secret \
         default_email_sender_address; do
  grep -q "^${v}\s*=" secrets.auto.tfvars && echo "OK   $v" || echo "MISSING $v"
done
cd ../..
```

Every line must read `OK`. `db_name`, `web_app_uri` and `google_redirect_uri` are derived in Terraform and need no tfvars entry.

- [ ] **Step 2: Rename the directory**

```bash
git mv products/protoapp products/meerkat
```

- [ ] **Step 3: Update the slug and display name**

In `products/meerkat/variables.tf`:

```hcl
variable "product" {
  description = "Product identifier (used in resource names, SSM paths and the X-Product-Id header)"
  type        = string
  default     = "meerkat"
}

variable "display_name" {
  description = "Human-facing product name (used in the SSM manifest the app repo reads)"
  type        = string
  default     = "Meerkat"
}
```

**Leave `capture_worker_ecr_repository` as `protoapp-capture-worker`.** Renaming an ECR repository forces replacement, which deletes the repository *and every image in it* — the capture worker would be undeployable until CI pushed a fresh image. The name is internal and invisible to users. Add a comment recording the decision:

```hcl
variable "capture_worker_ecr_repository" {
  # Deliberately still "protoapp-*" after the meerkat rename: renaming an ECR
  # repository destroys it and every stored image. The name is internal.
  description = "ECR repository holding the capture-worker image"
  type        = string
  default     = "protoapp-capture-worker"
}
```

- [ ] **Step 4: Remove the stale import blocks**

Delete `products/meerkat/secrets.tf:13-44` entirely. Those blocks adopt `/protoapp/*` paths that this stack no longer manages; leaving them makes Terraform try to import parameters into resources whose names have changed.

Update the file header comment from `// Per-product SSM, under /protoapp/*.` to `// Per-product SSM, under /meerkat/*.`

Every `name = "/${var.product}/..."` needs no edit — the slug variable drives them all.

- [ ] **Step 5: Plan — expect creates, not renames**

```bash
terraform -chdir=products/meerkat init
terraform -chdir=products/meerkat plan
```

Expected: 29 `aws_ssm_parameter` created at `/meerkat/*`, the manifest recreated, the listener rule updated in place (header value `protoapp` → `meerkat`), and the distribution updated in place (custom header value).

**`aws_ecr_repository` must not appear in the plan.** If it shows `must be replaced`, the Step 3 rename was applied anyway — revert it before continuing or the capture-worker images are destroyed.

The old `/protoapp/*` parameters are **not** destroyed — they left state when the import blocks were deleted. That is deliberate: it leaves a rollback path.

- [ ] **Step 6: Apply and confirm both paths exist**

```bash
terraform -chdir=products/meerkat apply
aws ssm get-parameters-by-path --path /meerkat --recursive --query 'length(Parameters)'
aws ssm get-parameters-by-path --path /protoapp --recursive --query 'length(Parameters)'
```

Both must be non-zero. There is never a window where neither exists.

- [ ] **Step 7: Cut the application over, then verify**

Deploy the app reading `/meerkat/*` (via the `/meerkat/manifest` `ssm.productPrefix` field), then:

```bash
curl -s -o /dev/null -w 'api %{http_code}\n' https://protoapp.xyz/api/health
```

Must return 200. A 502 or 503 means the ECS task cannot read its new parameter paths — check the task's IAM policy covers `/meerkat/*`.

- [ ] **Step 8: Delete the old parameters**

Only after Step 7 passes:

```bash
aws ssm get-parameters-by-path --path /protoapp --recursive \
  --query 'Parameters[].Name' --output text | tr '\t' '\n' | \
  while read -r p; do aws ssm delete-parameter --name "$p"; done
```

- [ ] **Step 9: Commit**

```bash
git add -A products/meerkat
git commit -m "refactor(meerkat)!: rename product protoapp -> meerkat

Directory, slug, 29 SSM paths, X-Product-Id value and ECR repository renamed in
one pass. protoapp.xyz becomes an umbrella zone; this product moves to
meerkat.protoapp.xyz in a follow-up.

BREAKING CHANGE: the app must read /meerkat/* instead of /protoapp/*."
```

---

## Task 9: Move meerkat to meerkat.protoapp.xyz

Additive — both URLs serve throughout. This costs nothing extra because the platform wildcard cert already covers both names, and it keeps Meta and TikTok working through their app review.

**Files:**
- Modify: `products/meerkat/main.tf` (aliases), `variables.tf` (domain)

**Interfaces:**
- Consumes: Task 8's renamed stack.
- Produces: meerkat served at `meerkat.protoapp.xyz`.

- [ ] **Step 1: Add the new name as an extra alias, keeping the old one primary**

In `products/meerkat/main.tf`, in the module call:

```hcl
  # Transitional: apex stays primary while OAuth callbacks are re-registered.
  extra_aliases = ["www.${var.domain_name}", "meerkat.protoapp.xyz"]
```

- [ ] **Step 2: Add the DNS record for the new name**

Append to `products/meerkat/domain.tf`:

```hcl
# Transitional record. Both protoapp.xyz and meerkat.protoapp.xyz resolve to the
# same distribution while external OAuth callbacks are re-registered.
resource "cloudflare_dns_record" "meerkat_subdomain" {
  zone_id = var.cloudflare_zone_id
  name    = "meerkat.protoapp.xyz"
  type    = "CNAME"
  content = module.product.cloudfront_domain_name
  ttl     = 1
  proxied = false
}
```

- [ ] **Step 3: Apply and verify both names serve**

```bash
terraform -chdir=products/meerkat apply
```

Wait for `Deployed`, then:

```bash
curl -s -o /dev/null -w 'old %{http_code}\n' https://protoapp.xyz/
curl -s -o /dev/null -w 'new %{http_code}\n' https://meerkat.protoapp.xyz/
curl -s -o /dev/null -w 'new api %{http_code}\n' https://meerkat.protoapp.xyz/api/health
```

All three must return 200 with a valid certificate — the wildcard covers the new name, so no TLS warning.

- [ ] **Step 4: Re-register external callbacks**

Start Meta and TikTok first — both gate redirect-domain changes behind app review, measured in days to weeks. The old URL stays live throughout, so nothing is blocked on them.

| Provider | New callback |
|---|---|
| Google | `https://meerkat.protoapp.xyz/api/auth/google/callback` |
| X | per X developer portal |
| LinkedIn | per LinkedIn app settings |
| Meta | **app review required** |
| Threads | per Meta app settings |
| TikTok | **app review required** |
| Pinterest | per Pinterest app settings |
| GitHub OAuth | `https://meerkat.protoapp.xyz/api/auth/github/callback` |
| Stripe | webhook endpoint → `https://meerkat.protoapp.xyz/api/webhooks/stripe` |

- [ ] **Step 5: Flip the primary domain**

Only once every provider above accepts the new URL. In `products/meerkat/variables.tf`:

```hcl
variable "domain_name" {
  description = "Domain served by this product"
  type        = string
  default     = "meerkat.protoapp.xyz"
}
```

In `products/meerkat/main.tf`, empty the transitional aliases:

```hcl
  extra_aliases = []
```

**This takes two applies, and a `moved` block will not work here.** `module.product.cloudflare_dns_record.app[0]` is already occupied — Task 7 moved the apex record into it. The module manages exactly one record, whose `name` follows `var.domain`. So the transitional record must be destroyed *before* the module's record is renamed onto that name, or Cloudflare rejects the duplicate CNAME mid-apply.

**Apply A — retire the transitional record.** Delete `cloudflare_dns_record.meerkat_subdomain` from `domain.tf`, leaving `domain_name` at `protoapp.xyz` for now:

```bash
terraform -chdir=products/meerkat apply
```

Expected: one record destroyed, nothing else. `meerkat.protoapp.xyz` stops resolving; the apex keeps serving.

**Apply B — rename the module's record.** Now set `domain_name` to `meerkat.protoapp.xyz` as above, empty `extra_aliases`, and delete `cloudflare_dns_record.www_to_cloudfront` (it pointed at the apex).

```bash
terraform -chdir=products/meerkat apply
```

Expected: the module's record updated in place from `protoapp.xyz` to `meerkat.protoapp.xyz`, the www record destroyed, the distribution's aliases updated in place.

The gap between the two applies is a few minutes of `meerkat.protoapp.xyz` not resolving. Acceptable, and it avoids a failed apply.

Because `var.domain_name` changed, `web_app_uri` and `google_redirect_uri` in `secrets.tf` re-derive automatically.

- [ ] **Step 6: Rebuild the webapp, apply, verify**

Rebuild with `VITE_API_URL=https://meerkat.protoapp.xyz` and `VITE_GOOGLE_REDIRECT_URL=https://meerkat.protoapp.xyz/api/auth/google/callback`, sync to S3, invalidate.

```bash
terraform -chdir=products/meerkat apply
curl -s -o /dev/null -w 'new %{http_code}\n' https://meerkat.protoapp.xyz/
curl -s -o /dev/null -w 'new api %{http_code}\n' https://meerkat.protoapp.xyz/api/health
aws ssm get-parameter --name /meerkat/web_app_uri --query 'Parameter.Value' --output text
```

The SSM value must read `https://meerkat.protoapp.xyz`.

No redirect is configured from the apex — these are personal projects with no inbound links worth preserving. `protoapp.xyz` is now free for an umbrella page.

- [ ] **Step 7: Commit**

```bash
git add products/meerkat/
git commit -m "feat(meerkat): serve from meerkat.protoapp.xyz

Additive cutover — both names served while OAuth callbacks were re-registered,
then the apex alias was dropped. protoapp.xyz is now free for the umbrella."
```

---

## Task 10: Move sjocamp to sjocamp.protoapp.xyz

Hard cutover with ~5-15 minutes of downtime on `app.sjocamp.co`. Serving both names would need a transition cert spanning two Cloudflare zones; that complexity is not worth buying for a personal project.

**Files:**
- Modify: `products/sjocamp/variables.tf`, `main.tf`, `domain.tf`

**Interfaces:**
- Consumes: Task 6's migrated stack, Task 2's platform cert.
- Produces: sjocamp served at `sjocamp.protoapp.xyz`.

- [ ] **Step 1: Point the stack at the umbrella zone and cert**

In `products/sjocamp/variables.tf`:

```hcl
variable "domain_name" {
  description = "Domain served by this product"
  type        = string
  default     = "sjocamp.protoapp.xyz"
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for protoapp.xyz (the umbrella zone)"
  type        = string
  default     = "e1fcf5e6c9b60043f75049228a8e3088"
}
```

In `products/sjocamp/main.tf`, swap the cert to the platform wildcard:

```hcl
  platform_acm_certificate_arn = data.terraform_remote_state.platform.outputs.acm_certificate_arn
```

- [ ] **Step 2: Remove the sjocamp.co cert and its validation record**

In `products/sjocamp/domain.tf`, delete `aws_acm_certificate.ssl_cert`, the `acm_validation` locals, and `cloudflare_dns_record.acm_validation`. They belong to a zone this stack no longer serves from.

`sjocamp.co`'s apex landing page is managed outside this repo and is untouched.

- [ ] **Step 3: Plan — expect one in-place distribution update**

```bash
terraform -chdir=products/sjocamp init
terraform -chdir=products/sjocamp plan
```

Expected: distribution `updated in-place` (alias and cert together), a new Cloudflare record in the protoapp.xyz zone, the old `app.sjocamp.co` record destroyed, the old cert destroyed, and SSM `web_app_uri` / `google_redirect_uri` updated.

**The distribution must not be replaced.** Alias and certificate changes are in-place operations.

- [ ] **Step 4: Apply, accepting the downtime**

```bash
terraform -chdir=products/sjocamp apply
```

`app.sjocamp.co` stops serving immediately; `sjocamp.protoapp.xyz` becomes available after propagation.

```bash
id=$(terraform -chdir=products/sjocamp output -raw cloudfront_distribution_id)
aws cloudfront get-distribution --id "$id" --query 'Distribution.Status' --output text
curl -s -o /dev/null -w 'new %{http_code}\n' https://sjocamp.protoapp.xyz/
curl -s -o /dev/null -w 'new api %{http_code}\n' https://sjocamp.protoapp.xyz/api/health
```

- [ ] **Step 5: Re-register sjocamp's four integrations**

| Provider | New value |
|---|---|
| Google OAuth | `https://sjocamp.protoapp.xyz/api/auth/google/callback` |
| Stripe | webhook endpoint + billing portal return URL |
| Resend | webhook endpoint |
| Sentry | allowed origins |

- [ ] **Step 6: Rebuild the webapp and verify end to end**

Rebuild with `VITE_API_URL=https://sjocamp.protoapp.xyz`, sync, invalidate. Then confirm a full login round-trip through Google works.

- [ ] **Step 7: Commit**

```bash
git add products/sjocamp/
git commit -m "feat(sjocamp): serve from sjocamp.protoapp.xyz

Hard cutover from app.sjocamp.co, using the shared protoapp.xyz wildcard cert.
Brief downtime accepted rather than issuing a two-zone transition cert.
sjocamp.co's landing page is unaffected."
```

---

## Task 11: New-project template and documentation

**Files:**
- Create: `products/_template/main.tf`, `variables.tf`
- Modify: `README.md`, `WEBAPP_DEPLOYMENT.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the documented path for adding project N+1.

- [ ] **Step 1: Write products/_template/main.tf**

The leading underscore keeps it out of any `products/*` glob.

```hcl
# Template for a new subdomain project. Copy to products/<slug>/, replace every
# PROJECT_SLUG, pick an unused alb_rule_priority, then:
#   aws s3 mb s3://<slug>-terraform-state
#   terraform init && terraform apply
#
# Then add the product's ECS task definition and service in this directory,
# wiring load_balancer.target_group_arn to module.product.target_group_arn.

terraform {
  required_version = ">= 1.2.0"

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.0" }
  }

  backend "s3" {
    bucket = "PROJECT_SLUG-terraform-state"
    key    = "state/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

provider "cloudflare" {}

data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket = "protoapp-infra-terraform-state"
    key    = "state/terraform.tfstate"
    region = var.aws_region
  }
}

module "product" {
  source = "../../modules/product"

  product      = var.product
  display_name = var.display_name
  domain       = "${var.product}.${data.terraform_remote_state.platform.outputs.zone_domain}"
  aws_region   = var.aws_region

  platform_alb_dns_name        = data.terraform_remote_state.platform.outputs.alb_dns_name
  platform_alb_listener_arn    = data.terraform_remote_state.platform.outputs.alb_listener_http_arn
  platform_vpc_id              = data.terraform_remote_state.platform.outputs.vpc_id
  platform_acm_certificate_arn = data.terraform_remote_state.platform.outputs.acm_certificate_arn

  cloudflare_zone_id                  = data.terraform_remote_state.platform.outputs.cloudflare_zone_id
  cloudfront_cache_policy_id          = data.terraform_remote_state.platform.outputs.cloudfront_api_cache_policy_id
  cloudfront_origin_request_policy_id = data.terraform_remote_state.platform.outputs.cloudfront_api_origin_request_policy_id
  cloudfront_spa_function_arn         = data.terraform_remote_state.platform.outputs.cloudfront_spa_function_arn

  # Unique per project. sjocamp 100, meerkat 200, new projects from 300 by 10.
  alb_rule_priority = 300
}
```

`variables.tf`:

```hcl
variable "product" {
  description = "Product slug — also the subdomain label"
  type        = string
  default     = "PROJECT_SLUG"
}

variable "display_name" {
  description = "Human-facing product name"
  type        = string
  default     = "PROJECT_SLUG"
}

variable "aws_region" {
  description = "AWS region (must match platform)"
  type        = string
  default     = "us-east-1"
}
```

- [ ] **Step 2: Rewrite the README sections**

Replace README.md's "Adding a new product (future)" with:

```markdown
## Adding a new project

Every project is a subdomain of `protoapp.xyz`: a static SPA on S3 + CloudFront
with `/api/*` forwarded to the shared ALB.

1. `cp -r products/_template products/<slug>` and replace every `PROJECT_SLUG`
2. Pick an unused `alb_rule_priority` — sjocamp 100, meerkat 200, new projects
   from 300 in steps of 10. AWS rejects duplicates.
3. `aws s3 mb s3://<slug>-terraform-state`
4. Add the ECS task definition and service in `products/<slug>/`, wiring
   `load_balancer.target_group_arn` to `module.product.target_group_arn`
5. `terraform init && terraform apply`
6. Create the project's database and user on the shared RDS instance
7. Populate `/<slug>/*` SSM via a gitignored `secrets.auto.tfvars`

### Session cookies must be host-only

`protoapp.xyz` is not on the Public Suffix List, so a cookie scoped to
`.protoapp.xyz` is readable *and writable* by every sibling subdomain. Set
session cookies with no `Domain=` attribute and `SameSite=Lax` minimum.
Cross-project SSO is a non-goal; see the design spec for the sanctioned path if
that ever changes.

### Limits

The ALB allows 100 rules per listener, one per project — roughly 95 projects.
```

Also update the "Shared vs per-product" table: ACM cert and Cloudflare DNS move to `platform`; CloudFront policies and the SPA function are shared.

- [ ] **Step 3: Update WEBAPP_DEPLOYMENT.md**

Replace the hardcoded sjocamp example with a manifest-driven one:

```markdown
## Deploy commands

Read ids from the product's SSM manifest rather than hardcoding them:

```bash
PRODUCT=meerkat
MANIFEST=$(aws ssm get-parameter --name "/$PRODUCT/manifest" --query 'Parameter.Value' --output text)
BUCKET=$(echo "$MANIFEST" | jq -r '.aws.webappS3Bucket')
DIST=$(echo "$MANIFEST" | jq -r '.aws.cloudfrontDistributionId')

aws s3 sync ./dist "s3://$BUCKET/" --delete
aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/*"
```
```

Update the architecture diagram to show subdomains, and note that `.github/workflows/webapp.yml` still carries hardcoded protoapp values and should read the manifest the same way.

- [ ] **Step 4: Validate the template parses**

```bash
terraform fmt -check -recursive products/_template modules/
```

`terraform init` is not run — the backend bucket is a placeholder.

- [ ] **Step 5: Commit**

```bash
git add products/_template README.md WEBAPP_DEPLOYMENT.md
git commit -m "docs: add project template and rewrite for the module-based flow

New projects are now cp -r products/_template plus a slug and a priority."
```

---

## Post-implementation verification

```bash
# Both products serve on their new subdomains
curl -s -o /dev/null -w 'meerkat %{http_code}\n' https://meerkat.protoapp.xyz/
curl -s -o /dev/null -w 'sjocamp %{http_code}\n' https://sjocamp.protoapp.xyz/

# Each API routes to its own target group
curl -s -o /dev/null -w 'meerkat api %{http_code}\n' https://meerkat.protoapp.xyz/api/health
curl -s -o /dev/null -w 'sjocamp api %{http_code}\n' https://sjocamp.protoapp.xyz/api/health

# The catch-all is closed: no header means 404, not someone's database
ALB=$(terraform -chdir=platform output -raw alb_dns_name)
curl -s -o /dev/null -w 'unrouted %{http_code}\n' "http://$ALB/api/health"

# All three stacks are clean
for d in platform products/meerkat products/sjocamp; do
  terraform -chdir=$d plan -detailed-exitcode >/dev/null 2>&1
  echo "$d exit=$?"   # 0 = clean
done
```

## Known follow-up work

- `.github/workflows/webapp.yml` still carries hardcoded protoapp values.
- Host capacity: each new project adds an ECS service to the single `t4g.large`. CPU on a burstable instance is the binding constraint, not memory. Tracked separately.
- Session cookies must be verified host-only in both products before a third project ships. This is application code, outside this plan.
