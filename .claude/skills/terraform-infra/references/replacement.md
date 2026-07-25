# What forces replacement

Terraform replaces a resource when an immutable attribute changes. The plan says
`must be replaced` and names the attribute with `# forces replacement`. On a
stateful resource that is data loss.

Confirm against the provider docs rather than memory — attributes marked
"Forces new resource" are the ones that matter:
https://registry.terraform.io/providers/hashicorp/aws/latest/docs

## The ones that bite in a module migration

| Resource | Attribute | Cost of replacement |
|---|---|---|
| `aws_s3_bucket` | `bucket` | **Data loss** — objects are not migrated |
| `aws_cloudfront_distribution` | few; most changes are in-place | ~20 min rebuild, site down |
| `aws_lb_target_group` | `name`, `port`, `protocol`, `target_type`, `vpc_id` | Targets re-register, brief API gap |
| `aws_ecs_service` | `name`, `cluster`, `launch_type` | Service recreated |
| `aws_cloudfront_origin_access_control` | `name` | Bucket policy references it — 403 window if mis-ordered |
| `aws_cloudfront_function` | `name`, `runtime` | Distributions referencing it must update |
| `aws_cloudfront_cache_policy` / `origin_request_policy` | `name` | Cannot delete while attached |
| `aws_ecr_repository` | `name` | **Destroys the repository and every image in it** |
| `aws_db_instance` | `engine`, `identifier` (without careful handling) | **Data loss** |
| `aws_cloudwatch_log_group` | `name` | Historical logs lost |
| `aws_launch_configuration` / `_template` | `image_id`, most fields | New instances only |

Two deserve special care because the damage is invisible in the plan summary:

**`aws_ecr_repository.name`** — renaming destroys the repository *and its
images*. A rename that looks cosmetic leaves a service undeployable until CI
pushes again. Repository names are internal; leave them alone during a product
rename and note why.

**`aws_s3_bucket.bucket`** — bucket names are cosmetic and need not match the
domain a site serves. When migrating an existing bucket into a module, pass the
live name as an override. Renaming buys nothing and costs the contents.

## The name-override pattern

A shared module generating names by convention will rename — and therefore
replace — every resource of an existing consumer. Give the module an override
input for each replacement-forcing name:

```hcl
variable "s3_bucket_name" {
  description = "Override the bucket name. Bucket names are cosmetic and need not match the serving domain."
  type        = string
  default     = null
}

locals {
  s3_bucket_name = coalesce(var.s3_bucket_name, "${var.product}-webapp")
}
```

Existing consumers pass their live names and migrate with no replacement. New
consumers omit them and get the convention. The gate is mechanical: if the plan
shows a replacement, an override is missing or wrong.

Capture live names before editing:

```bash
terraform -chdir=<stack> state list
terraform -chdir=<stack> state show <address> | grep -E '^\s+name\s+='
```

## Things that are not replacements but still surprise

- **`default_tags` reconciliation.** Importing into a stack whose provider sets
  different `default_tags` shows a tag diff. Harmless — but confirm it is *only*
  tags before applying.
- **`origin_id` on a CloudFront distribution.** An internal identifier linking an
  origin to its cache behaviour. Renaming is in-place and inert as long as both
  sides agree.
- **Document-shaped resources** (`aws_ssm_parameter` holding JSON, IAM policy
  documents). A shared module can silently render *fewer fields* than the live
  value. The plan shows an ordinary in-place update, or nothing at all if the
  value is marked sensitive — no replacement, no warning. Diff the rendered
  output against the live value:

  ```bash
  aws ssm get-parameter --name /product/manifest --query 'Parameter.Value' --output text \
    | python3 -c "import json,sys; print(sorted(json.load(sys.stdin)))"
  ```

## Guarding what must not be destroyed

```hcl
lifecycle {
  prevent_destroy = true
}
```

Turns an accidental destroy into a plan-time error. Worth it on databases, state
buckets, and any resource consumed by another stack — since
`terraform_remote_state` creates no dependency the owning stack can see.

Note `prevent_destroy` blocks the plan entirely, including intentional
destroys; removing it is a deliberate two-step. That friction is the point.
