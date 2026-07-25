# Refactoring Terraform state safely

Three declarative blocks change what state tracks without changing
infrastructure. All three appear in `terraform plan`, which is the reason to
prefer them over the CLI equivalents — you can review the state change before it
happens.

## `moved` — re-address within one state file

```hcl
moved {
  from = aws_s3_bucket.webapp_bucket
  to   = module.product.aws_s3_bucket.webapp
}
```

Handles renames and moves into or out of modules. Nothing in AWS changes; only
the address in state.

**Counted or keyed resources need the index.** If the destination uses `count`,
the target is `module.product.cloudflare_dns_record.app[0]`. Omitting the index
fails.

**Cross-resource-type moves are provider-dependent.** Terraform's docs: *"Each
resource type has a separate schema so objects of different types are not
typically compatible. You can always use the `moved` block to change the name of
a resource, but some providers also let you change an object from one resource
type to another."*

This bites with provider aliases. `aws_alb_target_group` and
`aws_lb_target_group` map to the same AWS API resource, but `moved` compares
**type names**, not schemas, and the AWS provider does not implement a state
move between them. Terraform 1.7.5 errors:

```
Error: Resource type mismatch
This statement declares a move from aws_alb_target_group.ecs_target to
module.product.aws_lb_target_group.api, which is a resource of a different type.
```

The workaround is `removed` + `import` (below), which keeps the previewability
that made `moved` attractive.

**You cannot move a `resource` into a `data` block.**

**Keep `moved` blocks — do not delete them after applying.** Terraform's docs are
explicit that removing one is a breaking change: any configuration still at the
old address will plan to *delete* the object rather than move it. Retain them so
the upgrade path survives. Deleting is only safe for a private module where you
know every consumer has already applied.

## `import` — adopt an existing resource

```hcl
import {
  to = aws_acm_certificate.wildcard
  id = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
}

resource "aws_acm_certificate" "wildcard" {
  # config must match the real resource
}
```

The plan shows `will be imported`. **If it shows `will be created` instead, the
ID is wrong** — and applying would build a duplicate alongside the original.
That is the single most important thing to check on an import.

ID formats vary by resource: an ARN for ACM, a bucket name for S3,
`<zone_id>/<record_id>` for a Cloudflare DNS record. Get the real value from
live state or the API rather than constructing it:

```bash
terraform -chdir=<stack> state show <address> | grep -E '^\s+(id|arn)\s+='
```

Adopted resources commonly show one in-place diff for tags, when the destination
stack's provider sets different `default_tags`. Confirm the diff is *only* tags
before applying.

Once satisfied, an `import` block is a no-op on later plans, so leaving it in
place is harmless.

## `removed` — stop managing without destroying

Terraform 1.7+:

```hcl
removed {
  from = aws_alb_target_group.ecs_target
  lifecycle {
    destroy = false
  }
}
```

Without `destroy = false` this destroys the real resource. With it, Terraform
forgets the resource and leaves it running.

Terraform's docs give the rationale directly: it *"lets you preview the results
of the operation, which makes it a safer way to remove resources"* than
`terraform state rm`.

## Replacing a cross-type `moved`

Pair them, in one apply:

```hcl
removed {
  from = aws_alb_target_group.ecs_target
  lifecycle { destroy = false }
}

import {
  to = module.product.aws_lb_target_group.api
  id = "arn:aws:elasticloadbalancing:...:targetgroup/ecs-target-group/4ca6ff25"
}
```

Net effect matches a state move, but it is previewable. Leave a comment saying
why it is not a `moved` block, or a future reader will "fix" it back into one
that cannot work.

## Moving between state files

`moved` only works within one state. Across stacks:

1. `import` in the destination, apply. Both stacks now track the resource.
2. `terraform state pull > backup.json` in the source.
3. Remove from the source's config **and** state before any apply there.
4. Verify the source plans clean and the resource still exists.

`terraform state rm` forgets; it does not delete. But config-without-state plans
a create, and state-without-config plans a destroy — neither intermediate state
is safe to apply.

## Child modules need their own `required_providers`

A child module resolves provider source addresses from **its own**
`required_providers`, not the root's. A module using a non-`hashicorp` provider
without declaring it makes Terraform assume `hashicorp/<name>` and fail `init` —
standalone *and* in every consuming root stack, no matter what the root declares.

```hcl
terraform {
  required_providers {
    aws        = { source = "hashicorp/aws",           version = "~> 5.0" }
    cloudflare = { source = "cloudflare/cloudflare",   version = "~> 5.0" }
  }
}
```

Declare every provider the module uses. No `provider` configuration blocks and
no `backend` in a child module — those stay with the root, which passes
configured providers down.

## Verifying a refactor

```bash
terraform -chdir=<stack> init
terraform -chdir=<stack> validate
terraform -chdir=<stack> plan -detailed-exitcode; echo "exit=$?"
```

`exit=0` means the refactor was a true no-op. `exit=2` needs every change
enumerated and justified. Any `must be replaced` means a name override is wrong —
fix the input value, never bend the module to accommodate one consumer.
