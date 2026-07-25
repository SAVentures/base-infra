# protoapp.xyz as a multi-project subdomain platform

**Date:** 2026-07-25
**Status:** Approved design, not yet implemented

## Context

`protoapp.xyz` becomes an umbrella zone hosting several independent prototype
projects, one per subdomain. The product currently served at the `protoapp.xyz`
apex — a social media scheduling AI — is renamed **meerkat** and moves to
`meerkat.protoapp.xyz`. **sjocamp** moves from `app.sjocamp.co` to
`sjocamp.protoapp.xyz`. New projects follow the same shape.

Every project is a full product: a static SPA on S3 + CloudFront, plus its own
API service on the shared ECS cluster behind the shared ALB.

All projects are prototypes. Products that later justify marketing spend will
move to their own apex domains; the design must make that move cheap.

These are personal projects with no availability commitment. Short downtime
during migration is acceptable and is traded deliberately for a simpler plan.

## Goals

- One reusable Terraform module for the product shape, replacing copy-paste.
- Both existing products migrated onto it, with zero resource replacement.
- New projects addable in ~30 lines of Terraform.
- The eventual move of any product to its own apex domain is a one-line change
  plus external re-registration — no infrastructure redesign.

## Non-goals

- Cross-project single sign-on. Explicitly rejected (see Identity below).
- Migrating any product to a dedicated domain now.
- Retiring `sjocamp.co`. Its apex landing page is managed outside this repo
  (`products/sjocamp/domain.tf:29`) and is untouched; only the app moves off
  `app.sjocamp.co`.
- Host right-sizing or Savings Plan purchases. Tracked separately; see Capacity.

## Current state

| Concern | Where it lives today |
|---|---|
| Wildcard cert `*.protoapp.xyz` | `products/protoapp/domain.tf:1-9` (already issued) |
| Cloudflare zone settings | `products/protoapp/domain.tf:51-79` |
| Shared ALB + 404 default listener | `platform/alb.tf:18-31` |
| Per-product routing | target group + `X-Product-Id` listener rule |
| Header injection | each product's CloudFront origin `custom_header` |
| State | one S3 bucket per stack, three stacks total |

`products/sjocamp/` is the clean template: every account-global CloudFront
resource name is namespaced with `${var.product}`.
`products/protoapp/` is the pre-split legacy stack and hardcodes six such names,
so it cannot be cloned as-is.

### Identity is already fully separated

| | meerkat | sjocamp |
|---|---|---|
| Database | `base_db` | `sjocamp` |
| JWT secret | own `secrets.auto.tfvars` | own `secrets.auto.tfvars` |
| Google OAuth client | own | own |

## Target architecture

```
platform/                      # + cloudflare provider
  zone.tf                      # *.protoapp.xyz cert, zone settings, apex DNS
  cloudfront-shared.tf         # cache policy, origin-request policy, SPA function
  outputs.tf                   # + acm_cert_arn, cloudflare_zone_id

modules/product/               # extracted from products/sjocamp
  cloudfront.tf                # S3 + OAC + distribution + aliases
  alb-routing.tf               # target group + X-Product-Id listener rule
  ecs-service.tf               # task definition + service
  domain.tf                    # Cloudflare DNS record for the subdomain
  manifest.tf                  # SSM /{product}/manifest
  variables.tf outputs.tf

products/meerkat/              # renamed from products/protoapp/
  main.tf                      # module call + moved blocks
  capture-worker.tf            # meerkat-only, deliberately outside the module
  secrets.tf secret-variables.tf secrets.auto.tfvars
products/sjocamp/
products/<new>/                # ~30 lines
```

The CloudFront cache policy, origin-request policy and SPA-routing function are
byte-identical across both products today and are account-level reusable
resources. They move to `platform/` and are referenced by ID, which also
eliminates the entire name-collision class.

The capture worker stays in `products/meerkat/`. It has one consumer; a
`count`-gated block in a shared module would be speculative generality.

## Module interface

Name overrides exist so migrating an existing product produces a zero-change
plan. Every listed attribute forces resource replacement when changed.

| Input | meerkat passes | sjocamp passes | new project default |
|---|---|---|---|
| `product` | `meerkat` | `sjocamp` | — |
| `domain` | `meerkat.protoapp.xyz` | `sjocamp.protoapp.xyz` | `<slug>.protoapp.xyz` |
| `s3_bucket_name` | `protoapp.xyz-webapp` | `app.sjocamp.co-webapp` | `protoapp-<slug>-webapp` |
| `target_group_name` | `ecs-target-group` | `sjocamp-api-tg` | `<slug>-api-tg` |
| `ecs_service_name` | `api_service` | existing | `<slug>-api` |
| `oac_name` | `webapp-oac` | `sjocamp-webapp-oac` | `<slug>-webapp-oac` |
| `alb_rule_priority` | 200 | 100 | 300+, steps of 10 |

`domain` is a pure input. Nothing else in the module derives a hostname from any
other source, which is what makes a later move to a real apex a one-line change.

S3 bucket names are cosmetic — they need not match the serving domain. Existing
buckets keep their names permanently; there is no rename and no data migration.

## Migration plan

Each phase is independently revertible. Phases run per product.

### Phase 0 — Preconditions

- Verify `products/protoapp/secrets.auto.tfvars` contains all eight values
  adopted via `import` blocks at `products/protoapp/secrets.tf:13-44`.
  **If `jwt_secret` is absent and gets regenerated during the slug rename, every
  logged-in meerkat session is invalidated.** Do not proceed until confirmed.
- Confirm each product's session cookie is host-only (see Identity).

### Phase 1 — Hoist zone and shared CloudFront resources to platform

Add the `cloudflare` provider to `platform/`. Adopt existing resources with
declarative `import` blocks (already in use at `products/protoapp/secrets.tf:13`,
so the toolchain supports them). `import` adopts without mutating; the ACM
certificate is never reissued.

Moves: `aws_acm_certificate.ssl_cert`, `cloudflare_dns_record.acm_validation`,
`cloudflare_zone_setting.*`.

Shared CloudFront policies and the SPA function are created fresh in `platform/`
under new names, then products are repointed, then the per-product originals are
deleted. Order matters: a policy cannot be deleted while attached to a
distribution. Policy-ID changes are in-place distribution updates — CloudFront
does not replace a distribution for them.

**Gate:** `terraform plan` in `platform/` shows only additions; plans in both
product stacks show only in-place updates.

### Phase 2 — Refactor both products onto the module

All moves are intra-state — each product keeps its own state bucket, so this is
an address change within one state file. `moved` blocks express it declaratively;
no `terraform state mv` is used anywhere.

**Gate: `terraform plan` must print `No changes`.** Any resource showing
`must be replaced` means a missing name override. Fix the input; never approve
the plan.

### Phase 3 — Slug rename (meerkat only)

29 SSM parameters re-path from `/protoapp/*` to `/meerkat/*`. Create the new
paths first, cut the application over, then remove the old ones — there is never
a window where neither exists.

Also renamed: the `X-Product-Id` value, the manifest path, the
`protoapp-capture-worker` ECR repository, and the `products/protoapp/` directory.

`protoapp-infra-terraform-state` and `protoapp-terraform-state` keep their names.
Renaming state buckets buys nothing and risks the state itself.

### Phase 4 — Domain move

For meerkat, additive and reversible — both URLs serve simultaneously throughout:

1. Add the new alias to the existing distribution (in-place, ~5 min propagation).
2. Add the Cloudflare CNAME pointing at that same distribution.
3. Re-register external callbacks — the old URL stays live, so there is no
   deadline.
4. Rebuild the webapp with new `VITE_*` values; update `web_app_uri` and
   `google_redirect_uri` in SSM.
5. Verify, then drop the old alias.

For sjocamp, a single apply swapping alias, certificate and DNS together, then
re-register its four integrations. Brief downtime accepted.

No redirect is configured from either old URL. These are personal projects with
no inbound links or SEO worth preserving.

**meerkat requires no certificate work.** The existing cert covers both
`protoapp.xyz` (`domain_name`) and `meerkat.protoapp.xyz` (via the
`*.protoapp.xyz` SAN at `products/protoapp/domain.tf:3`).

**sjocamp does a hard cutover instead.** `app.sjocamp.co` and
`sjocamp.protoapp.xyz` sit in different Cloudflare zones, and a distribution
accepts only one certificate, so serving both names at once would need a
transition cert spanning two zones. That complexity is not worth buying here:
these are personal projects and brief downtime is acceptable. Swap the alias and
the certificate to the shared wildcard in a single apply and accept ~5-15 minutes
of CloudFront propagation during which `app.sjocamp.co` is unavailable.

**meerkat keeps the additive cutover**, because it costs nothing extra — the
existing certificate already covers both names, so it is literally one added
alias and one DNS record — and because Meta and TikTok gate redirect-domain
changes behind app review. Keeping the old URL live means those integrations
continue working during review rather than breaking for its duration.

External re-registration required:

| Product | Integrations |
|---|---|
| meerkat | Google, X, LinkedIn, Meta, Threads, TikTok, Pinterest, GitHub OAuth; Stripe webhook |
| sjocamp | Google OAuth; Stripe webhook + billing portal; Resend webhook; Sentry |

Meta and TikTok gate redirect-domain changes behind app review — days to weeks of
lead time. Start those first; the additive cutover means nothing else blocks on
them.

### Phase 5 — Fix the catch-all

`products/protoapp/alb-routing.tf:22-36` is a header-*less* rule at priority 1000
matching `/api/*`. Any project that omits its `X-Product-Id` header, or lands at a
lower priority, silently reaches meerkat's API and database.

Replace it with an explicit `X-Product-Id = meerkat` rule at priority 200. The
listener's existing 404 default (`platform/alb.tf:23-30`) becomes the only
fallback, so misconfiguration fails loudly.

This is a latent defect independent of the rest of this work and should ship even
if later phases slip.

## Conventions

**ALB rule priorities.** sjocamp 100, meerkat 200, new projects from 300 in steps
of 10. ALB rejects duplicate priorities. Ceiling is the ALB quota of 100 rules per
listener, so roughly 95 projects.

**Routing key.** Rules match `X-Product-Id`, not `host_header`. Header values
survive a domain change; host rules would need editing every time a product moves
to a real apex, which is a planned event.

**Bucket naming.** New projects use `protoapp-<slug>-webapp`. Dotted names such as
`foo.protoapp.xyz-webapp` are avoided — they are legal but unreachable over HTTPS
in virtual-hosted style. Existing dotted buckets are grandfathered.

## Identity and cookies

Cross-project SSO is a non-goal. Each project keeps its own login.

**Constraint: session cookies must be host-only** — no `Domain=` attribute,
`SameSite=Lax` minimum. `protoapp.xyz` is not on the Public Suffix List, so a
cookie scoped to `.protoapp.xyz` is readable *and writable* by every sibling
subdomain; one compromised prototype could then forge sessions for meerkat.

This is application code, not Terraform. It must hold in meerkat and sjocamp
before a third project ships.

Host-only cookies do not log users out of anything. Each subdomain holds an
independent session and they coexist; a user is simply never signed into one
product by virtue of being signed into another.

**If SSO is ever wanted**, the sanctioned path is a central auth service at
`auth.protoapp.xyz` issuing short-lived tokens via redirect, with each product
setting its own host-only cookie and verifying asymmetrically against public
JWKS. A shared parent-domain cookie with a shared signing key is explicitly
rejected: any compromised subdomain would steal every session, and it breaks
entirely once a product moves to its own apex. `auth.protoapp.xyz` would be an
ordinary project on this module.

## Capacity

Each project with an API adds an ECS service to the single `t4g.large` host.
Current reservations are ~2656 MB of ~7800 MB usable and 1152 of 2048 CPU units;
three known incoming workloads take that to roughly 3008 MB and 1536 CPU units.
Memory is comfortable; CPU on a burstable instance is the binding constraint.

Host topology and Savings Plan decisions are deliberately out of scope here and
tracked separately.

## Verification gates

| Phase | Gate |
|---|---|
| 0 | All eight imported secret values present in `secrets.auto.tfvars` |
| 1 | `platform/` plan shows only additions; product plans only in-place updates |
| 2 | `terraform plan` prints `No changes` in both product stacks |
| 3 | New SSM paths readable by the app before old paths are removed |
| 4 (meerkat) | Both old and new URLs serve correctly before the old alias is dropped |
| 4 (sjocamp) | `sjocamp.protoapp.xyz` serves with a valid certificate after the swap |
| 5 | A request with no `X-Product-Id` returns 404, not a meerkat response |

## Risks

These are personal prototype projects. Brief downtime is acceptable and is
deliberately traded for a simpler migration. The mitigations kept below are the
ones that are near-free and guard against *self-inflicted, slow-to-undo* damage —
not against downtime.

| Risk | Mitigation | Kept because |
|---|---|---|
| Name override missed → resource replaced | Zero-diff plan gate at Phase 2 | Reading a plan is free; a recreated CloudFront distribution costs ~20 min |
| `jwt_secret` regenerated → mass logout | Phase 0 precondition check | One grep; silently signs out every user |
| Policy deleted while attached | Create → repoint → delete ordering | Apply simply fails otherwise |
| Meta/TikTok review delays meerkat cutover | Additive migration; old URL stays live | Costs nothing — same cert covers both names |
| Sibling subdomain forges sessions | Host-only cookie constraint | Security, not availability |
| `app.sjocamp.co` down during cutover | **Accepted** | Personal project; ~5-15 min |

## Follow-up work

- CI is still hardcoded to protoapp values
  (`.github/workflows/webapp.yml`, per `WEBAPP_DEPLOYMENT.md`). Multi-project
  deploys should read the SSM `/{product}/manifest`, which exists for this.
- `README.md` "Adding a new product" and the shared-vs-per-product table need
  rewriting for the module-based flow.
