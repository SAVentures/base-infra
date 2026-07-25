# Product Tiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the prototype/product distinction explicit in Terraform — tier governs domain placement, log retention, and alarms — and make promoting a prototype a supported three-line change.

**Architecture:** `modules/product` gains a `tier` input. `domain` stays a pure input; placement is enforced by a `validation` block, not derived inside the module. Log retention resolves from tier and is exported so product stacks apply the same value to their own ECS log groups. Alarms are created only for `tier = "product"`, pointing at one shared SNS topic in `platform/`.

**Tech Stack:** Terraform ≥1.15, AWS provider ~>6.0, Cloudflare provider ~>5.0, S3 remote state (one bucket per stack).

**Spec:** `docs/superpowers/specs/2026-07-25-product-tiers-design.md`

## Global Constraints

- **This is Terraform, not application code.** The TDD cycle maps to: write config → `terraform validate` → `terraform plan` and assert on the diff → apply → verify against AWS. **The plan is the test.**
- **The gate: no resource may show `must be replaced` or `will be destroyed`.** Absolute, in every task. A replaced `aws_s3_bucket` destroys live webapp assets; a replaced `aws_cloudfront_distribution` drops the site for ~20 minutes.
- **Save the plan and apply that file.** `terraform -chdir=<stack> plan -out=tfplan` then `terraform -chdir=<stack> apply tfplan`. A bare `apply` re-plans at apply time, so what you reviewed is not provably what runs. `tfplan` contains full variable values — delete it after applying.
- **`terraform plan -detailed-exitcode`**: `0` = no changes, `1` = error, `2` = changes present.
- **Region is `us-east-1`** for everything.
- **Do not rename state buckets.** platform → `protoapp-infra-terraform-state`, protoapp/meerkat → `protoapp-terraform-state`, sjocamp → `sjocamp-terraform-state`.
- **Never run `aws ssm put-parameter` by hand.** Secrets flow from gitignored `secrets.auto.tfvars` through Terraform.
- **Commit after every task.** These are infrastructure changes; clean history is the rollback mechanism.
- **Do not add the `domain` validation before Task 6.** `products/protoapp` currently declares `domain = "protoapp.xyz"`, which is the umbrella zone itself and satisfies neither branch of the condition. Landing the check early breaks that stack at plan time.
- Personal prototype projects — brief downtime is acceptable. Do not add complexity to avoid it.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `platform/alerts.tf` | **Create.** SNS topic + email subscription for product alarms | 1 |
| `platform/outputs.tf` | **Modify.** Export `alerts_topic_arn`, `alb_arn_suffix` | 1 |
| `modules/product/variables.tf` | **Modify.** `tier`, `umbrella_zone_domain`, `log_retention_days`, `alerts_topic_arn`, `platform_alb_arn_suffix`; rename cert var; `local.log_retention_days`; (Task 6) `domain` validation | 2,3,4,6 |
| `modules/product/cloudfront.tf` | **Modify.** Use renamed cert var (`:127`) and resolved retention (`:140`) | 2,3 |
| `modules/product/alarms.tf` | **Create.** Two target-group alarms, products only | 4 |
| `modules/product/outputs.tf` | **Modify.** Export `log_retention_days` | 3 |
| `products/sjocamp/main.tf` | **Modify.** `tier = "product"` + new inputs | 2,3,4 |
| `products/sjocamp/ecs-service.tf` | **Modify.** Retention from module output (`:3`) | 3 |
| `products/protoapp/main.tf` | **Modify.** `tier = "prototype"` + new inputs | 2,3,4 |
| `products/protoapp/ecs-service.tf` | **Modify.** Retention from module output (`:3`) | 3 |
| `products/protoapp/capture-worker.tf` | **Modify.** Retention from module output (`:16`) | 3 |
| `products/_template/main.tf` | **Modify.** Tier + new inputs for new projects | 5 |
| `README.md`, `CLAUDE.md` | **Modify.** Document the two tiers | 5 |
| `docs/superpowers/plans/2026-07-25-protoapp-subdomain-platform.md` | **Modify.** Retire task 10 | 5 |

---

### Task 1: Platform alerts infrastructure

**Files:**
- Create: `platform/alerts.tf`
- Modify: `platform/outputs.tf`

**Interfaces:**
- Produces: platform outputs `alerts_topic_arn` (string, SNS topic ARN) and `alb_arn_suffix` (string, e.g. `app/k8sALB/924fd36a9899c766`). Tasks 4 consumes both.

- [ ] **Step 1: Create the SNS topic and subscription**

Create `platform/alerts.tf`:

```hcl
# Single shared alerting destination. Per-product topics buy nothing — the
# alarms already name the product, and one subscription is one confirmation
# click instead of N.
resource "aws_sns_topic" "alerts" {
  name = "platform-alerts"

  tags = {
    Name = "Platform alerts"
  }
}

# NOTE: AWS creates email subscriptions in "pending confirmation" and sends a
# link that must be clicked. terraform apply reports success while the
# subscription is inert. See Step 5.
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "hello@shubhanshu.dev"
}
```

- [ ] **Step 2: Add the platform outputs**

Append to `platform/outputs.tf`:

```hcl
output "alerts_topic_arn" {
  value       = aws_sns_topic.alerts.arn
  description = "Shared SNS topic for product alarms; consumed by modules/product"
}

output "alb_arn_suffix" {
  value       = aws_lb.k8s_alb.arn_suffix
  description = "ALB ARN suffix for CloudWatch dimensions. The alb_arn output is the full ARN and is NOT usable as a dimension."
}
```

- [ ] **Step 3: Validate and plan**

Run:
```bash
terraform -chdir=platform validate
terraform -chdir=platform plan -out=tfplan
```

Expected: `Plan: 2 to add, 0 to change, 0 to destroy.` — the topic and the subscription. Outputs alone create nothing.

**Gate:** no `must be replaced`, no `will be destroyed`. If anything else appears, stop and investigate before applying.

- [ ] **Step 4: Apply**

```bash
terraform -chdir=platform apply tfplan && rm -f platform/tfplan
```

- [ ] **Step 5: Confirm the email subscription (MANUAL — apply is not enough)**

Check your inbox at `hello@shubhanshu.dev` for "AWS Notification - Subscription Confirmation" and click the link. Then verify it took:

```bash
aws sns list-subscriptions-by-topic \
  --topic-arn "$(terraform -chdir=platform output -raw alerts_topic_arn)" \
  --query 'Subscriptions[].{Endpoint:Endpoint,Arn:SubscriptionArn}' --output json
```

Expected: `Arn` is a real ARN. If it reads `PendingConfirmation`, the link has not been clicked and **alarms will fire into a void** — do not proceed to Task 4 until this is confirmed.

- [ ] **Step 6: Commit**

```bash
git add platform/alerts.tf platform/outputs.tf
git commit -m "feat(platform): add shared SNS alerts topic for product alarms"
```

---

### Task 2: Tier variable and certificate rename

Pure refactor plus one unused variable. **The deliverable is a zero-diff plan on all three stacks** — that is what proves the rename touched no infrastructure.

**Files:**
- Modify: `modules/product/variables.tf`
- Modify: `modules/product/cloudfront.tf:127`
- Modify: `products/sjocamp/main.tf`, `products/protoapp/main.tf`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `var.tier` (string, `"prototype"` | `"product"`) and `var.umbrella_zone_domain` (string) on `modules/product`. Tasks 3, 4 and 6 read `var.tier`; Task 6 reads `var.umbrella_zone_domain`. Renames `var.platform_acm_certificate_arn` → `var.acm_certificate_arn`.

- [ ] **Step 1: Add the tier variables**

Add to `modules/product/variables.tf`, immediately after the `environment` variable:

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
```

- [ ] **Step 2: Rename the certificate variable**

In `modules/product/variables.tf`, change the declaration:

```hcl
variable "acm_certificate_arn" {
  type        = string
  description = "Certificate covering this product's domain. Prototypes pass the platform wildcard; products pass their own cert, created in their stack."
}
```

It was named `platform_acm_certificate_arn`, which was wrong — sjocamp already passes its own cert, not the platform's.

- [ ] **Step 3: Update the module's use of it**

In `modules/product/cloudfront.tf:127`, inside `viewer_certificate`:

```hcl
    acm_certificate_arn      = var.acm_certificate_arn
```

- [ ] **Step 4: Update the sjocamp call site**

In `products/sjocamp/main.tf`, in the `module "product"` block, replace the `platform_acm_certificate_arn` line and add the tier lines:

```hcl
  product     = var.product
  domain      = var.domain_name
  environment = var.environment
  tier        = "product"

  umbrella_zone_domain = data.terraform_remote_state.platform.outputs.zone_domain

  platform_alb_dns_name     = data.terraform_remote_state.platform.outputs.alb_dns_name
  platform_alb_listener_arn = data.terraform_remote_state.platform.outputs.alb_listener_http_arn
  platform_vpc_id           = data.terraform_remote_state.platform.outputs.vpc_id
  acm_certificate_arn       = aws_acm_certificate.ssl_cert.arn
```

- [ ] **Step 5: Update the protoapp call site**

In `products/protoapp/main.tf`, same edit with the other tier:

```hcl
  product     = var.product
  domain      = var.domain_name
  environment = var.environment
  tier        = "prototype"

  umbrella_zone_domain = data.terraform_remote_state.platform.outputs.zone_domain

  platform_alb_dns_name     = data.terraform_remote_state.platform.outputs.alb_dns_name
  platform_alb_listener_arn = data.terraform_remote_state.platform.outputs.alb_listener_http_arn
  platform_vpc_id           = data.terraform_remote_state.platform.outputs.vpc_id
  acm_certificate_arn       = data.terraform_remote_state.platform.outputs.acm_certificate_arn
```

protoapp is knowingly non-conforming here — it declares `tier = "prototype"` while still serving `protoapp.xyz`. That is why the `domain` validation is deferred to Task 6.

- [ ] **Step 6: Validate**

```bash
for s in platform products/protoapp products/sjocamp; do
  terraform -chdir=$s init >/dev/null && terraform -chdir=$s validate
done
```

Expected: `Success!` for all three.

`products/_template/main.tf` still references the old `platform_acm_certificate_arn` name at this point. That is deliberate — the template has no backend and is never initialised, so it cannot break a plan. It is updated in Task 5.

- [ ] **Step 7: Prove zero diff — this is the test**

```bash
for s in products/protoapp products/sjocamp; do
  terraform -chdir=$s plan -detailed-exitcode -lock=false >/dev/null 2>&1
  echo "$s exit=$?"
done
```

Expected: `exit=0` for **both**. A variable rename and an unused new variable must not move any infrastructure.

If either returns `2`, run the plan without `-detailed-exitcode` and read the diff. A change here means the rename touched something it should not have — do not proceed.

- [ ] **Step 8: Commit**

```bash
git add modules/product/variables.tf modules/product/cloudfront.tf \
        products/sjocamp/main.tf products/protoapp/main.tf
git commit -m "refactor(product): add tier input, rename platform_acm_certificate_arn

The variable was never 'the platform cert' — sjocamp has always passed its
own. Renaming it to acm_certificate_arn matches how both call sites use it.

tier is declared but unused until the retention and alarm tasks. Verified
zero plan diff on both product stacks."
```

---

### Task 3: Log retention by tier

**Files:**
- Modify: `modules/product/variables.tf`
- Modify: `modules/product/cloudfront.tf:140`
- Modify: `modules/product/outputs.tf`
- Modify: `products/sjocamp/ecs-service.tf:3`
- Modify: `products/protoapp/ecs-service.tf:3`, `products/protoapp/capture-worker.tf:16`

**Interfaces:**
- Consumes: `var.tier` from Task 2.
- Produces: module output `log_retention_days` (number). Product stacks apply it to their own ECS log groups.

- [ ] **Step 1: Add the retention variable**

Add to `modules/product/variables.tf`:

```hcl
variable "log_retention_days" {
  description = "Override log retention. Defaults by tier: prototype 7, product 90."
  type        = number
  default     = null
}
```

- [ ] **Step 2: Resolve it in the existing locals block**

`modules/product/variables.tf` already ends with a `locals` block. Add one entry to it:

```hcl
  log_retention_days = coalesce(var.log_retention_days, var.tier == "product" ? 90 : 7)
```

- [ ] **Step 3: Use it for the CloudFront log group**

In `modules/product/cloudfront.tf:140`:

```hcl
  retention_in_days = local.log_retention_days
```

- [ ] **Step 4: Export it**

Append to `modules/product/outputs.tf`:

```hcl
output "log_retention_days" {
  value       = local.log_retention_days
  description = "Tier-resolved retention. Product stacks apply this to their own ECS log groups so the tier governs all of a product's logs."
}
```

- [ ] **Step 5: Apply it in the product stacks**

`products/sjocamp/ecs-service.tf:3`:

```hcl
  retention_in_days = module.product.log_retention_days
```

`products/protoapp/ecs-service.tf:3`:

```hcl
  retention_in_days = module.product.log_retention_days
```

`products/protoapp/capture-worker.tf:16`:

```hcl
  retention_in_days = module.product.log_retention_days
```

Leave `platform/kafka.tf:75` at `7` — Kafka is shared infrastructure, not a product, and has no tier.

- [ ] **Step 6: Verify the prototype is a genuine no-op**

```bash
terraform -chdir=products/protoapp plan -detailed-exitcode -lock=false >/dev/null 2>&1; echo "protoapp exit=$?"
```

Expected: `exit=0`. A prototype resolves to 7, which is what is already live.

- [ ] **Step 7: Plan the product stack and read the diff**

```bash
terraform -chdir=products/sjocamp plan -out=tfplan
```

Expected: `Plan: 0 to add, 2 to change, 0 to destroy.` Both changes are `~ retention_in_days = 7 -> 90`, on:
- `module.product.aws_cloudwatch_log_group.cloudfront` (`/aws/cloudfront/sjocamp-webapp`)
- `aws_cloudwatch_log_group.api` (`/sjocamp/api`)

**Gate:** no replacements, no destroys.

- [ ] **Step 8: Apply**

```bash
terraform -chdir=products/sjocamp apply tfplan && rm -f products/sjocamp/tfplan
```

- [ ] **Step 9: Verify against AWS**

```bash
aws logs describe-log-groups \
  --query 'logGroups[].{Name:logGroupName,Retention:retentionInDays}' --output table
```

Expected: `/sjocamp/api` and `/aws/cloudfront/sjocamp-webapp` at `90`; `api-logs`, `capture-worker-logs`, `/aws/cloudfront/webapp`, `kafka-logs` still at `7`.

- [ ] **Step 10: Commit**

```bash
git add modules/product/variables.tf modules/product/cloudfront.tf modules/product/outputs.tf \
        products/sjocamp/ecs-service.tf products/protoapp/ecs-service.tf products/protoapp/capture-worker.tf
git commit -m "feat(product): resolve log retention from tier

Prototypes keep 7 days, products get 90. The module owns only the CloudFront
log group, so the resolved value is exported and each product stack applies it
to its own ECS log groups — the tier governs all of a product's logs without
the module reaching outside its boundary."
```

---

### Task 4: Alarms for products

**Files:**
- Modify: `modules/product/variables.tf`
- Create: `modules/product/alarms.tf`
- Modify: `products/sjocamp/main.tf`, `products/protoapp/main.tf`

**Interfaces:**
- Consumes: `var.tier` (Task 2); platform outputs `alerts_topic_arn` and `alb_arn_suffix` (Task 1).
- Produces: nothing consumed by later tasks.

**Prerequisite:** Task 1 Step 5 must be confirmed. Alarms pointing at an unconfirmed subscription fire silently.

- [ ] **Step 1: Add the alarm variables**

Add to `modules/product/variables.tf`:

```hcl
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

- [ ] **Step 2: Create the alarms**

Create `modules/product/alarms.tf`:

```hcl
# Products only. A prototype must never page anyone — that is the point of the
# tier. Both alarms hang off the target group this module owns, so they answer
# "is this product's API broken" without reaching into the product's stack.

resource "aws_cloudwatch_metric_alarm" "no_healthy_hosts" {
  count = var.tier == "product" ? 1 : 0

  alarm_name          = "${var.product}-no-healthy-hosts"
  alarm_description   = "${var.product} has no healthy targets — the API is down."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = 60
  evaluation_periods  = 2

  # breaching, not notBreaching: CloudWatch stops emitting HealthyHostCount
  # entirely once the target group has zero registered targets — that is
  # every task down, the exact outage this alarm exists to catch. Missing
  # data here means "nothing is registered," not "nothing happened." This is
  # the opposite of target_5xx below, whose metric is genuinely absent during
  # a quiet period.
  treat_missing_data = "breaching"

  alarm_actions = [var.alerts_topic_arn]
  ok_actions    = [var.alerts_topic_arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.api.arn_suffix
    LoadBalancer = var.platform_alb_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  count = var.tier == "product" ? 1 : 0

  alarm_name          = "${var.product}-target-5xx"
  alarm_description   = "${var.product} is returning 5xx from the application."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 10
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.alerts_topic_arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.api.arn_suffix
    LoadBalancer = var.platform_alb_arn_suffix
  }
}
```

The two alarms treat missing data **differently**, and the asymmetry is the point:

- `target_5xx` uses `notBreaching`. `HTTPCode_Target_5XX_Count` is only emitted when there is traffic, so a quiet period must not read as an outage.
- `no_healthy_hosts` uses `breaching`. `HealthyHostCount` stops being emitted entirely once the target group has **zero registered targets** — every task down, which is precisely the outage this alarm exists to catch. Treating that as "not breaching" would make the alarm silent during the worst-case failure.

- [ ] **Step 3: Wire the sjocamp call site**

Add to the `module "product"` block in `products/sjocamp/main.tf`:

```hcl
  alerts_topic_arn        = data.terraform_remote_state.platform.outputs.alerts_topic_arn
  platform_alb_arn_suffix = data.terraform_remote_state.platform.outputs.alb_arn_suffix
```

- [ ] **Step 4: Wire the protoapp call site**

Add to the `module "product"` block in `products/protoapp/main.tf`. `platform_alb_arn_suffix` has no default so it is required even though a prototype creates no alarms:

```hcl
  platform_alb_arn_suffix = data.terraform_remote_state.platform.outputs.alb_arn_suffix
```

Do **not** pass `alerts_topic_arn` — a prototype has no alarm destination by design.

- [ ] **Step 5: Verify the prototype creates nothing**

```bash
terraform -chdir=products/protoapp plan -detailed-exitcode -lock=false >/dev/null 2>&1; echo "protoapp exit=$?"
```

Expected: `exit=0`. Both alarms are `count = 0` for a prototype.

- [ ] **Step 6: Plan and apply the product stack**

```bash
terraform -chdir=products/sjocamp plan -out=tfplan
```

Expected: `Plan: 2 to add, 0 to change, 0 to destroy.` — `module.product.aws_cloudwatch_metric_alarm.no_healthy_hosts[0]` and `...target_5xx[0]`.

**Gate:** no replacements, no destroys.

```bash
terraform -chdir=products/sjocamp apply tfplan && rm -f products/sjocamp/tfplan
```

- [ ] **Step 7: Verify the alarms exist and are not already alarming**

```bash
aws cloudwatch describe-alarms \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Actions:AlarmActions}' --output table
```

Expected: two alarms, both `OK` or `INSUFFICIENT_DATA`, each with the platform SNS topic in `Actions`. `ALARM` on `sjocamp-no-healthy-hosts` means sjocamp is genuinely down — investigate before continuing.

- [ ] **Step 8: Commit**

```bash
git add modules/product/variables.tf modules/product/alarms.tf \
        products/sjocamp/main.tf products/protoapp/main.tf
git commit -m "feat(product): add target-group alarms for products only

No-healthy-hosts and target 5xx, both count=0 for prototypes — a broken
prototype must not page anyone. target_5xx uses notBreaching so a quiet
period does not read as an outage; no_healthy_hosts uses breaching because
a missing HealthyHostCount means zero registered targets, which IS the
outage."
```

---

### Task 5: Template and documentation

**Files:**
- Modify: `products/_template/main.tf`
- Modify: `README.md`, `CLAUDE.md`
- Modify: `docs/superpowers/plans/2026-07-25-protoapp-subdomain-platform.md`

**Interfaces:**
- Consumes: the full module contract from Tasks 2–4.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Update the new-project template**

In `products/_template/main.tf`, in the `module "product"` block, add the tier inputs. A new project is a prototype by default:

```hcl
  product     = var.product
  domain      = "${var.product}.${data.terraform_remote_state.platform.outputs.zone_domain}"
  environment = var.environment
  tier        = "prototype"

  umbrella_zone_domain = data.terraform_remote_state.platform.outputs.zone_domain

  acm_certificate_arn     = data.terraform_remote_state.platform.outputs.acm_certificate_arn
  platform_alb_arn_suffix = data.terraform_remote_state.platform.outputs.alb_arn_suffix
```

Also replace the existing `platform_acm_certificate_arn` line, which no longer exists as a variable.

- [ ] **Step 2: Retire task 10 in the old plan**

In `docs/superpowers/plans/2026-07-25-protoapp-subdomain-platform.md`, change the Task 10 heading and add a note directly beneath it:

```markdown
## Task 10: Move sjocamp to sjocamp.protoapp.xyz — RETIRED, DO NOT EXECUTE

> **Retired 2026-07-25.** Backwards under the tier policy: sjocamp shipped as
> the first production product and belongs on its own domain, which is where it
> already is. Kept rather than deleted so the history stays legible. See
> `docs/superpowers/specs/2026-07-25-product-tiers-design.md`.
```

Leave tasks 8 and 9 alone — they are still required, and are Phase 2.

- [ ] **Step 3: Document the tiers in README.md**

Replace the "Adding a new project" opening line, which currently asserts every project is a protoapp.xyz subdomain:

```markdown
## Tiers: prototype vs product

Every deployment is one of two tiers, set by `tier` on `modules/product`:

| | prototype | product |
|---|---|---|
| Domain | `<slug>.protoapp.xyz` | its own domain |
| Certificate | shared `*.protoapp.xyz` wildcard | its own, created in its stack |
| Log retention | 7 days | 90 days |
| Alarms | none | unhealthy hosts + target 5xx |

A prototype is disposable and may break quietly. A product is shipped software
and pages you. `modules/product` validates placement, so a prototype cannot be
put on a real domain and a product cannot squat the umbrella zone.

To promote a prototype, see the spec:
`docs/superpowers/specs/2026-07-25-product-tiers-design.md`.
```

- [ ] **Step 4: Document the tiers in CLAUDE.md**

Add to `CLAUDE.md` after the "Module boundary" section:

```markdown
## Tiers

`modules/product` takes `tier` = `prototype` | `product`. Prototypes live at
`<slug>.protoapp.xyz` on the shared wildcard cert with 7-day logs and no alarms;
products live on their own domain with their own cert, 90-day logs and two
target-group alarms. Placement is enforced by a `validation` block on `domain`,
not derived — `domain` stays a pure input so promotion is a three-line change.

Promotion needs a manually-created Cloudflare zone; Terraform owns everything
downstream of that. The SNS email subscription requires a confirmation click
that `apply` cannot perform.
```

- [ ] **Step 5: Verify nothing moved**

```bash
for s in products/protoapp products/sjocamp; do
  terraform -chdir=$s plan -detailed-exitcode -lock=false >/dev/null 2>&1
  echo "$s exit=$?"
done
terraform fmt -check -diff products/_template && echo "template parses and is formatted"
```

Expected: `exit=0` for both stacks — documentation changes nothing.

The template is checked with `fmt`, not `validate`: its backend names a bucket that does not exist (`PROJECT_SLUG-terraform-state`), so it can never be initialised, and `validate` without init fails for reasons unrelated to your edit. `fmt` parses the HCL, which is the only property that matters here.

- [ ] **Step 6: Commit**

```bash
git add products/_template/main.tf README.md CLAUDE.md \
        docs/superpowers/plans/2026-07-25-protoapp-subdomain-platform.md
git commit -m "docs: document the prototype/product tiers, retire plan task 10"
```

---

### Task 6: Enable placement enforcement — BLOCKED

> **Do not start this task until Phase 2 is complete.** Phase 2 is tasks 8 and 9
> of `docs/superpowers/plans/2026-07-25-protoapp-subdomain-platform.md`: rename
> the slug `protoapp` → `meerkat` and move it to `meerkat.protoapp.xyz`. Until
> that lands, `products/protoapp` declares `domain = "protoapp.xyz"` — the
> umbrella zone itself — and this validation fails its plan.

**Files:**
- Modify: `modules/product/variables.tf`

**Interfaces:**
- Consumes: `var.tier` and `var.umbrella_zone_domain` from Task 2.
- Produces: nothing.

- [ ] **Step 1: Confirm Phase 2 actually landed**

```bash
terraform -chdir=products/meerkat output 2>/dev/null | head -3
aws cloudfront list-distributions \
  --query 'DistributionList.Items[].Aliases.Items' --output json
```

Expected: an alias list containing `meerkat.protoapp.xyz` and **not** `protoapp.xyz`. If `protoapp.xyz` is still an alias, Phase 2 is incomplete — stop.

- [ ] **Step 2: Add the validation**

Add to the existing `domain` variable in `modules/product/variables.tf`:

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

Cross-variable references in `validation` require Terraform ≥1.9; this repo is on 1.15.8.

- [ ] **Step 3: Verify both stacks still plan clean**

```bash
for s in products/meerkat products/sjocamp; do
  terraform -chdir=$s plan -detailed-exitcode -lock=false >/dev/null 2>&1
  echo "$s exit=$?"
done
```

Expected: `exit=0` for both. A validation block creates nothing; it either passes or errors.

- [ ] **Step 4: Prove the validation actually rejects a violation**

This is the real test of this task — a validation that never fires is untested. Temporarily set `tier = "product"` in `products/meerkat/main.tf` and plan:

```bash
terraform -chdir=products/meerkat plan -lock=false 2>&1 | grep -A3 "Invalid value"
```

Expected: the plan **fails** with the placement error message, because a product may not serve a subdomain of the umbrella zone.

Then revert the file:

```bash
git checkout products/meerkat/main.tf
terraform -chdir=products/meerkat plan -detailed-exitcode -lock=false >/dev/null 2>&1; echo "reverted exit=$?"
```

Expected: `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add modules/product/variables.tf
git commit -m "feat(product): enforce tier placement at plan time

A prototype must serve <slug>.protoapp.xyz; a product may not serve the
umbrella zone or any subdomain of it, so nothing can re-squat the apex the way
protoapp did. Verified the validation rejects a deliberate violation."
```

---

## Verification: whole-plan gate

After Task 5 (Phase 1 complete):

```bash
for s in platform products/protoapp products/sjocamp; do
  terraform -chdir=$s plan -detailed-exitcode -lock=false >/dev/null 2>&1
  echo "$s exit=$?"
done
```

Expected: `exit=0` on all three — every intended change has been applied.

Then confirm the tier actually took effect:

```bash
aws logs describe-log-groups --query 'logGroups[].{Name:logGroupName,Retention:retentionInDays}' --output table
aws cloudwatch describe-alarms --query 'MetricAlarms[].AlarmName' --output json
```

Expected: sjocamp's two log groups at 90 and everything else at 7; exactly two alarms, both named `sjocamp-*`.

## Out of scope

- **Phase 2 (the meerkat move).** Tasks 8 and 9 of the earlier plan.
- **Guardrails.** No `prevent_destroy`, no deletion protection — explicitly rejected in the spec.
- **RDS backup posture.** `my-postgres-db` has 1-day retention, no Multi-AZ, no deletion protection, and holds sjocamp's live-payments database. Recorded as an open risk in the spec; retention is per-instance so it cannot vary by tier today.
