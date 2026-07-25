---
name: terraform-infra
description: Safe workflow for changing Terraform-managed AWS infrastructure — refactoring into modules, moving resources between state files, importing existing resources, and reading a plan for danger before applying. Use this whenever the task touches .tf files, terraform plan/apply/state/import output, an AWS resource that Terraform manages, or any question about whether a change will replace or destroy something. Also use it when splitting a monolithic stack into modules, hoisting shared resources between stacks, renaming a product or slug across SSM paths, or wiring a new service behind a shared ALB or CloudFront distribution — even if the user doesn't say "Terraform" explicitly.
---

# Terraform infrastructure changes

The whole game is this: **a Terraform plan tells you exactly what is about to
happen, and almost every infrastructure disaster is someone not reading it.**
A refactor that should be a no-op quietly becomes a destroy-and-recreate because
one string changed. This skill is about making that impossible to miss.

## The core loop

```bash
terraform -chdir=<stack> plan -out=tfplan   # save the exact plan
# read it — see "Reading a plan" below
terraform -chdir=<stack> apply tfplan       # apply exactly what you read
```

Save the plan and apply *that file*. `terraform apply` without a saved plan
re-plans at apply time, so what you reviewed is not provably what runs. The saved
plan contains full variable values — treat it as sensitive and delete it after.

`terraform plan -detailed-exitcode` makes "is this stack clean?" scriptable:

| Exit | Meaning |
|---|---|
| `0` | Succeeded, **no changes** |
| `1` | Error |
| `2` | Succeeded, **changes present** |

**Establish a baseline before editing anything.** If the stack is already dirty
you cannot tell your diff from pre-existing drift. Two common sources of
permanent drift: AMI IDs resolved from SSM "latest recommended" pointers (every
new AMI release makes the launch template want replacement), and anything using
`timestamp()`.

## Reading a plan

Scan for these in order. The first two are the ones that hurt.

1. **`must be replaced`** — destroy then create. On a stateful resource that is
   data loss. Stop and find which attribute forced it.
2. **`will be destroyed`** — did you intend to remove this from config?
3. **`will be created`** — genuinely new, or is Terraform failing to see an
   existing resource it should be adopting?
4. **`will be updated in-place`** — usually safe, but read what changed.

The summary line is not enough on its own. A plan can show a low destroy count
and still replace something, since a replacement counts as one add plus one
destroy.

When a refactor *should* be a no-op, state it as an explicit gate: **no
replacements, and every remaining change individually justifiable.** Literal
zero-diff is a good target but not always reachable — normalizing tags across two
previously-divergent stacks always produces a small in-place diff. What matters
is that nothing is replaced.

See `references/replacement.md` for which attributes force replacement.

## Refactoring without destroying

Changing a resource's address — renaming it, or moving it into a module — reads
to Terraform as "destroy the old, create the new" unless you say otherwise.

Prefer **declarative** state operations over CLI state commands, because they
appear in a plan and can be reviewed before touching anything:

| Goal | Use | Not |
|---|---|---|
| Rename / move into a module | `moved` block | `terraform state mv` |
| Adopt an existing resource | `import` block | `terraform import` |
| Stop managing without deleting | `removed` block, `lifecycle { destroy = false }` | `terraform state rm` |

The CLI equivalents mutate state the instant they run, with no preview and no
diff. The blocks are dry-runnable. That difference is the entire reason to prefer
them — if you reach for `terraform state mv`, ask what you lose by not being able
to review it first.

See `references/refactoring.md` for mechanics, including the cross-resource-type
restriction on `moved` that bites when a config uses a provider alias such as
`aws_alb_target_group` vs `aws_lb_target_group`.

## Working across multiple state files

Splitting a stack, or hoisting shared resources into a platform stack, moves a
resource between *state files*. `moved` blocks cannot do this — they only
re-address within one state.

A sequence that never leaves a resource unmanaged or destroyed:

1. **Adopt in the destination** with an `import` block, and apply. Both stacks
   now track the same real resource — a deliberate, brief overlap.
2. **Back up the source state** (`terraform state pull > backup.json`). Cheap
   insurance, especially where backends have no locking.
3. **Release from the source**: remove it from config *and* from state. Do both
   before any apply in that stack — config-only leaves a plan that wants to
   **destroy** the real resource.
4. **Verify** the source stack plans clean and the resource still exists in AWS.

Ordering matters more than speed. `terraform state rm` forgets a resource; it
does not delete it. But removing it from config while state still tracks it
produces a plan that genuinely will delete it.

## Cross-stack dependencies are convention, not enforcement

`data "terraform_remote_state"` is a one-directional read. The stack that *owns*
a resource has no idea anyone consumes it — Terraform's dependency graph does not
cross state files. Deleting a shared resource shows up as an ordinary destroy in
its own stack, with no warning that other stacks reference it.

If a resource is consumed across stacks, `lifecycle { prevent_destroy = true }`
is the only real guard, and a comment naming the consumers is the minimum.

## Secrets and generated values

Route secrets through variables and a gitignored `*.auto.tfvars`, not manual
console or CLI writes — a hand-set value is invisible to the config and gets
clobbered on the next apply.

Before any change that re-creates parameters (a slug rename, a path change),
**verify every value is present in tfvars first**. A secret Terraform cannot see
gets regenerated, and regenerating a signing key silently invalidates every
active session. Check, then change.

## When something must go down

Not every change can be zero-downtime, and buying zero-downtime has a real
complexity cost. Ask what the change is worth: a personal project absorbs a few
minutes of downtime far more cheaply than it absorbs a transition-certificate
dance across two DNS zones. State the downtime plainly and let the owner decide
rather than defaulting to the elaborate path.

`create_before_destroy` is the usual tool for avoiding a gap — but it **fails on
resources with a fixed unique name**, because the replacement collides with the
original. It works with `name_prefix`; it breaks with a hardcoded `name`.

## Module boundaries

When extracting a shared module, the test for whether something belongs inside
is whether its *content* is the same across consumers — not whether every
consumer has one.

Things whose content is irreducibly per-consumer (compute environment blocks,
descriptor documents assembling per-product identifiers) belong outside, even
though every consumer has one. Pulling them in means threading a large map of
pass-through variables, which is worse than the duplication it removes. Worse, an
under-specified shared version *silently drops fields* consumers relied on — and
that failure does not appear as a replacement in a plan, so it slips past the
usual gate. Diff the rendered output against the live value whenever a module
absorbs anything document-shaped.

Give the module explicit **name override inputs** for every replacement-forcing
attribute. Existing consumers pass their live names and migrate with no
replacement; new consumers omit them and get the convention.

## AWS constraints that shape designs

See `references/aws-limits.md` for verified quotas. The ones that most often
change an architecture:

- **Target groups per ALB: 100, not adjustable.** This — not the rules quota — is
  the real ceiling on services behind one shared ALB.
- **Custom cache policies and origin request policies: 20 each per account.**
  Per-product copies do not scale; share them.
- **One ACM certificate per CloudFront distribution.** Serving two hostnames from
  different zones during a migration needs one cert covering both.
- **An alternate domain name (CNAME) attaches to only one distribution**
  account-wide.

## Agents

Three agents in `.claude/agents/` handle specific roles: `terraform-reviewer`
(audit a plan before apply), `terraform-migrator` (execute a refactor under a
no-apply rule), `terraform-cost-auditor` (find spend). Delegate when the task is
big enough that a focused pass helps.
