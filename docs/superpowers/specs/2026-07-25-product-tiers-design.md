# Product Tiers: prototype vs product

**Date:** 2026-07-25
**Status:** Approved, not yet implemented

## Goal

Make explicit in Terraform a distinction the repo already runs implicitly:

- **prototype** — disposable. Lives at `<slug>.protoapp.xyz`, a subdomain of the
  umbrella zone. Short log retention, no alarms. Downtime is uninteresting.
- **product** — real, shipped software. Lives on its own domain. Longer log
  retention, alarms wired to a human.

The tier governs **placement, log retention, and alarms**, and makes graduating a
prototype into a product a supported three-line change rather than a
reconstructed-from-memory migration.

## Context: what the audit found

The subdomain migration planned in
`docs/superpowers/plans/2026-07-25-protoapp-subdomain-platform.md` was executed
only in part. Tasks 1–7 and 11 landed (ALB catch-all closed, zone resources
hoisted to `platform/`, shared CloudFront policies, `modules/product` created,
both products migrated onto it, template written). **Tasks 8, 9 and 10 never
ran.** All 73 plan checkboxes are still unticked.

Verified against live AWS on 2026-07-25:

| Check | State |
|---|---|
| CloudFront aliases | `protoapp.xyz` + `www.protoapp.xyz`; `app.sjocamp.co` |
| Any `*.protoapp.xyz` subdomain | none — `meerkat.` and `sjocamp.protoapp.xyz` do not resolve |
| SSM prefixes | `/protoapp/*` (35), `/sjocamp/*` (13), `/platform/*` (12). No `/meerkat/*` |
| Sites serving | `protoapp.xyz`, `www.protoapp.xyz`, `app.sjocamp.co` all 200 |
| Wildcard cert | ISSUED, covers `protoapp.xyz`, `www.protoapp.xyz`, `*.protoapp.xyz`, valid to 2027-01-21 |

Two consequences shape this design:

1. **sjocamp is already where the new policy wants it.** It is a real product on
   its own domain. Plan task 10 would have moved it *onto* `sjocamp.protoapp.xyz`
   — backwards under this policy. That task is retired, not resumed.
2. **protoapp is the one genuine misalignment.** It is a prototype occupying
   `protoapp.xyz`, the umbrella apex itself, so the zone meant to be a shared
   namespace is squatted by a single product, and the apex cert and zone DNS are
   coupled to that product's distribution.

Nothing blocks either direction: the wildcard cert already covers every
subdomain, ALB `X-Product-Id` routing works, and `modules/product` already takes
`domain` as a pure input.

## The tiers already exist, unnamed

The two call sites differ today in exactly the way the tiers describe:

```hcl
# products/sjocamp/main.tf:32   — a product: own cert, created in its own stack
platform_acm_certificate_arn = aws_acm_certificate.ssl_cert.arn

# products/protoapp/main.tf:36  — a prototype: the shared umbrella wildcard
platform_acm_certificate_arn = data.terraform_remote_state.platform.outputs.acm_certificate_arn
```

The module variable is misnamed: it is not "the platform cert", it is "this
distribution's cert". sjocamp already proves the own-cert path works end to end.
This design therefore names and enforces an existing pattern; it does not
introduce a new mechanism.

## Design constraint we are preserving

`modules/product/variables.tf` says of `domain`:

> A pure input: nothing derives a hostname from any other source, so moving a
> product to its own apex is a one-line change.

That was deliberate, and it is what makes promotion cheap. **The module must not
compute hostnames.** Placement is therefore enforced by validation (fails at plan
time) rather than by construction (impossible to express). This was a considered
trade: compile-time safety is not worth breaking promotion for a decision made
once per project.

## Module contract changes — `modules/product`

### New inputs

```hcl
variable "tier" {
  description = "prototype = disposable, lives on a subdomain of the umbrella zone. product = real, lives on its own domain."
  type        = string
  validation {
    condition     = contains(["prototype", "product"], var.tier)
    error_message = "tier must be \"prototype\" or \"product\"."
  }
}

variable "umbrella_zone_domain" {
  description = "The umbrella zone (protoapp.xyz). Used only to validate placement."
  type        = string
}

variable "log_retention_days" {
  description = "Override log retention. Defaults by tier: prototype 7, product 90."
  type        = number
  default     = null
}

variable "alerts_topic_arn" {
  description = "SNS topic for product alarms. Required when tier = product; ignored for prototypes."
  type        = string
  default     = null

  validation {
    condition     = var.tier != "product" || var.alerts_topic_arn != null
    error_message = "alerts_topic_arn is required when tier = \"product\" — alarms with no destination are worse than no alarms."
  }
}

variable "platform_alb_arn_suffix" {
  description = "Shared ALB ARN suffix, required as a CloudWatch dimension for target-group alarms."
  type        = string
}
```

### Placement validation on `domain`

```hcl
validation {
  condition = var.tier == "prototype" ? (
    var.domain == "${var.product}.${var.umbrella_zone_domain}"
  ) : (
    var.domain != var.umbrella_zone_domain &&
    !endswith(var.domain, ".${var.umbrella_zone_domain}")
  )
  error_message = "A prototype must serve <product>.<umbrella zone>; a product must serve its own domain, not the umbrella zone or a subdomain of it."
}
```

Properties this buys:

- A prototype sits at exactly `<slug>.protoapp.xyz` — no drifting subdomain names.
- A product cannot sit on the umbrella zone *or its apex*, so nothing can
  re-squat `protoapp.xyz` the way protoapp does today. The audit finding becomes
  a plan-time error.
- Promotion remains a `domain` change plus a tier flip. No derived hostnames, no
  resource addresses move.

Cross-variable references in `validation` blocks require **Terraform ≥ 1.9**.
This became available with the 1.7.5 → 1.15.8 upgrade on 2026-07-25; on the old
CLI this approach was not expressible. Confirm at plan time during
implementation.

### Rename

`platform_acm_certificate_arn` → `acm_certificate_arn`. Module-internal variable
rename, no resource address change, zero infrastructure diff. Both call sites
update.

### Log retention

```hcl
locals {
  log_retention_days = coalesce(var.log_retention_days, var.tier == "product" ? 90 : 7)
}
```

Applied to `aws_cloudwatch_log_group.cloudfront` (`modules/product/cloudfront.tf:140`,
currently hardcoded `7`).

The module owns only the **CloudFront** log group. ECS log groups live in the
product stacks (`products/*/ecs-service.tf:3`, `products/protoapp/capture-worker.tf:16`),
all hardcoded to 7. The module therefore exports the resolved value:

```hcl
output "log_retention_days" {
  value       = local.log_retention_days
  description = "Tier-resolved retention; product stacks apply this to their own ECS log groups."
}
```

Each product stack references `module.product.log_retention_days` for its own log
groups, so the tier governs all of a product's logs without the module reaching
outside its boundary.

`platform/kafka.tf:75` is shared infrastructure, not a product, and keeps its own
retention.

### Alarms — products only

Two alarms on the target group the module already owns, both
`count = var.tier == "product" ? 1 : 0`:

| Alarm | Metric | Condition |
|---|---|---|
| Unhealthy hosts | `AWS/ApplicationELB` `UnHealthyHostCount` | `>= 1` for 2 consecutive periods |
| Target 5xx | `AWS/ApplicationELB` `HTTPCode_Target_5XX_Count` | `> 10` over 5 minutes |

Both require `TargetGroup` and `LoadBalancer` dimensions, hence the new
`platform_alb_arn_suffix` input.

A prototype gets no alarms by design — a broken prototype must not page anyone.

## Platform changes

```hcl
# platform/alerts.tf (new)
resource "aws_sns_topic" "alerts" { name = "platform-alerts" }

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "hello@shubhanshu.dev"
}
```

New outputs in `platform/outputs.tf`:

- `alerts_topic_arn`
- `alb_arn_suffix` — `aws_lb.k8s_alb.arn_suffix`; the existing `alb_arn` output is
  the full ARN and is not usable as a CloudWatch dimension.

**Manual step, unavoidable:** AWS creates email subscriptions in
`pending confirmation` and sends a link that must be clicked. `terraform apply`
will report success while the subscription is inert. Confirm the email before
treating alarms as live.

## Call sites at the end state (after Phase 2)

During Phase 1 meerkat is still `protoapp` at `protoapp.xyz` and knowingly
non-conforming; the row below describes where it lands once Phase 2 runs.

| | meerkat (was protoapp) | sjocamp |
|---|---|---|
| `tier` | `prototype` | `product` |
| `domain` | `meerkat.protoapp.xyz` | `app.sjocamp.co` |
| `acm_certificate_arn` | platform wildcard | own cert in its stack |
| `cloudflare_zone_id` | umbrella zone | sjocamp.co zone |
| Log retention | 7 (unchanged) | 7 → **90**, in-place |
| Alarms | none | 2 created |

## Implementation sequencing

The validation cannot land before meerkat moves: `products/protoapp` currently
declares `domain = "protoapp.xyz"`, which is the umbrella zone itself and
satisfies neither branch of the condition. Landing the check first breaks that
stack at plan time. Three phases:

**Phase 1 — mechanism, no enforcement.** Add `tier`, `umbrella_zone_domain`,
`log_retention_days`, `alerts_topic_arn`, `platform_alb_arn_suffix`; rename the
cert variable; add the SNS topic and platform outputs; wire retention and alarms.
Set `tier = "product"` on sjocamp and `tier = "prototype"` on protoapp. **Do not
add the `domain` validation yet.** protoapp is knowingly non-conforming during
this phase.

**Phase 2 — move meerkat.** Execute existing plan tasks 8 and 9: rename the slug
`protoapp` → `meerkat` (35 SSM parameters re-path from `/protoapp/*` to
`/meerkat/*`), move the domain to `meerkat.protoapp.xyz`, rename the directory to
`products/meerkat`. The state bucket stays `protoapp-terraform-state` — plan
constraint, do not rename state buckets. Before applying, verify every secret is
present in `secrets.auto.tfvars`: a value Terraform cannot see gets regenerated,
and regenerating `jwt_secret` invalidates every active session.

**Phase 3 — enable enforcement.** Add the `domain` validation. Both stacks now
conform, and the rule is enforced for every future project.

## Promotion: prototype → product

1. **Manual:** register the domain, create the Cloudflare zone, point the
   registrar's nameservers at it. Needs payment and NS changes; cannot be
   automated from here.
2. **Add the cert** to the product stack. Copy `products/sjocamp/domain.tf` — it
   is the working reference for a per-product cert plus its DNS validation record.
3. **Change four lines** in the module call: `tier = "product"`, the new `domain`,
   the new `cloudflare_zone_id`, and `acm_certificate_arn = aws_acm_certificate.ssl_cert.arn`.
4. **Plan, with the standard gate:** no replacements. The distribution updates its
   aliases and certificate **in place**, so the ~20-minute distribution rebuild is
   avoided.
5. **Re-register externally:** OAuth redirect URIs, Stripe webhook URL, `VITE_*`
   build-time variables, Resend sending domain. This is the part that actually
   breaks users, and none of it is in Terraform.

Retention moves to 90 and the alarms appear automatically from the tier flip.

`X-Product-Id` routing is untouched by a domain move — the ALB rule matches the
slug, not the hostname. That was the reason for choosing a header condition over
`host_header`, and promotion is where it pays off.

**Cutover, not dual-serving.** `extra_aliases` can serve old and new names
simultaneously, but the old `<slug>.protoapp.xyz` CNAME lives in the umbrella zone
while the module's DNS record follows the product to its new zone — so
dual-serving means hand-maintaining a second record for the transition. Given
that brief downtime is acceptable here, that machinery is not worth building.
`extra_aliases` remains the escape hatch if a future product genuinely cannot
blink.

Demotion (product → prototype) is not supported and not needed.

## Retired: plan task 10

Task 10 of `2026-07-25-protoapp-subdomain-platform.md` moves sjocamp to
`sjocamp.protoapp.xyz`. Under this policy that is backwards — sjocamp shipped as
the first production product and belongs on its own domain. Mark the task retired
in the plan with this reason rather than deleting it, so the history stays
legible.

## Out of scope

- **Guardrails.** No `prevent_destroy`, no deletion protection, no
  `lifecycle` blocks keyed off tier. Explicitly rejected: they obstruct the
  teardown speed that makes prototypes worth having.
- **The meerkat move itself.** Specified in plan tasks 8 and 9; this document only
  establishes the rule that requires it.
- **Per-tier database posture.** See below.

## Open risk: RDS backup posture

The shared RDS instance `my-postgres-db` has **1-day backup retention, no
Multi-AZ, and no deletion protection**, and it holds the sjocamp database, which
serves live Stripe payments.

Backup retention is a property of the instance, not of a database, so it **cannot
vary by tier** while every product shares one instance. The options are to raise
retention for everyone (retention itself is free; you pay for backup storage) or
to give products their own instance (real recurring cost).

Scoped out of this change deliberately. Recorded here so it is a decision on the
record rather than an oversight.

## Verification gate

Standard for this repo: `terraform plan` on all three stacks shows **no
`must be replaced` and no `will be destroyed`**. Expected in-place changes only:

- sjocamp CloudFront + ECS log groups: `retention_in_days` 7 → 90
- sjocamp: two new CloudWatch alarms
- platform: new SNS topic and subscription

`terraform plan -detailed-exitcode` must exit `0` on meerkat in Phase 1 — the tier
and retention values resolve to what is already live, so a prototype's plan is a
genuine no-op.
