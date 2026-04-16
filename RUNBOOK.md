# Runbook: migrate protoapp to the platform + product pattern

This PR restructures the existing infra into two Terraform stacks:

- `platform/` — shared: VPC, RDS, ECS cluster, ALB, Kafka, IAM roles, `/platform/rds/*` SSM
- `products/protoapp/` — protoapp-only: S3, CloudFront, ACM, ECS service, target group, listener rule, per-product SSM, Cloudflare DNS

**The code in this PR matches existing AWS resources exactly** (same names, same SSM paths, same config). After the migration, `terraform plan` on both stacks should show zero changes — nothing is recreated, nothing is modified. We're just relocating resources between Terraform states.

Everything still works while migration happens. No downtime.

## 0. Prerequisites

- AWS CLI authenticated
- Terraform >= 1.2
- `gh` CLI as protoappxyz
- Cloudflare provider API key at SSM `/cloudflare/api_key` (already exists)
- **Branch checked out locally**: `git checkout terraform-parameterize && git pull`

## 1. Create the new state bucket for protoapp product

```bash
aws s3api create-bucket --bucket protoapp-terraform-state --region us-east-1
aws s3api put-bucket-versioning --bucket protoapp-terraform-state --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket protoapp-terraform-state \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

## 2. Initialize both stacks

```bash
cd infra-setup/platform
terraform init   # uses existing protoapp-infra-terraform-state (unchanged)

cd ../products/protoapp
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your cloudflare_email
terraform init   # initializes fresh state in protoapp-terraform-state
```

## 3. Extract AWS IDs from the current platform state

Run these from `infra-setup/platform/` to get IDs we'll need for imports:

```bash
cd infra-setup/platform

CLOUDFRONT_ID=$(terraform state show aws_cloudfront_distribution.webapp_distribution | awk '/^ *id *=/ {gsub(/"/,"",$3); print $3; exit}')
ACM_CERT_ARN=$(terraform state show aws_acm_certificate.ssl_cert | awk '/^ *arn *=/ {gsub(/"/,"",$3); print $3; exit}')
OAC_ID=$(terraform state show aws_cloudfront_origin_access_control.webapp_oac | awk '/^ *id *=/ {gsub(/"/,"",$3); print $3; exit}')
CF_FUNCTION_ETAG=$(terraform state show aws_cloudfront_function.spa_routing | awk '/^ *etag *=/ {gsub(/"/,"",$3); print $3; exit}')
CACHE_POLICY_ID=$(terraform state show aws_cloudfront_cache_policy.api_cache_policy | awk '/^ *id *=/ {gsub(/"/,"",$3); print $3; exit}')
ORIGIN_REQ_POLICY_ID=$(terraform state show aws_cloudfront_origin_request_policy.api_origin_request_policy | awk '/^ *id *=/ {gsub(/"/,"",$3); print $3; exit}')
TARGET_GROUP_ARN=$(terraform state show aws_alb_target_group.ecs_target | awk '/^ *arn *=/ {gsub(/"/,"",$3); print $3; exit}')
LISTENER_RULE_ARN=$(terraform state show aws_lb_listener_rule.alb_listener_rule_api_http | awk '/^ *arn *=/ {gsub(/"/,"",$3); print $3; exit}')
ECS_CLUSTER_NAME=$(terraform state show aws_ecs_cluster.ecs_cluster | awk '/^ *name *=/ {gsub(/"/,"",$3); print $3; exit}')
TASK_DEF_ARN=$(terraform state show aws_ecs_task_definition.task_definition | awk '/^ *arn *=/ {gsub(/"/,"",$3); print $3; exit}')
ACM_VALIDATION_RECORD_IDS=$(terraform state list | grep 'cloudflare_record.acm_validation')

# Cloudflare record IDs need a per-record lookup
CF_ROOT_RECORD_ID=$(terraform state show cloudflare_record.root_to_cloudfront | awk '/^ *id *=/ {gsub(/"/,"",$3); print $3; exit}')
CF_WWW_RECORD_ID=$(terraform state show cloudflare_record.www_to_cloudfront | awk '/^ *id *=/ {gsub(/"/,"",$3); print $3; exit}')
CF_ZONE_ID="e1fcf5e6c9b60043f75049228a8e3088"

echo "CloudFront distribution: $CLOUDFRONT_ID"
echo "ACM cert: $ACM_CERT_ARN"
echo "Target group: $TARGET_GROUP_ARN"
echo "Listener rule: $LISTENER_RULE_ARN"
echo "Task def: $TASK_DEF_ARN"
```

Keep this terminal open — you'll use these variables in subsequent steps.

## 4. Remove resources from platform state

Run from `infra-setup/platform/`:

```bash
# SSM parameters (17)
terraform state rm aws_ssm_parameter.db_endpoint
terraform state rm aws_ssm_parameter.db_username
terraform state rm aws_ssm_parameter.db_password
terraform state rm aws_ssm_parameter.db_name
terraform state rm aws_ssm_parameter.jwt_secret
terraform state rm aws_ssm_parameter.google_client_id
terraform state rm aws_ssm_parameter.google_client_secret
terraform state rm aws_ssm_parameter.google_redirect_uri
terraform state rm aws_ssm_parameter.web_app_uri
terraform state rm aws_ssm_parameter.stripe_publishable_key
terraform state rm aws_ssm_parameter.stripe_secret_key
terraform state rm aws_ssm_parameter.stripe_webhook_secret
terraform state rm aws_ssm_parameter.resend_api_key
terraform state rm aws_ssm_parameter.default_email_sender_address
terraform state rm aws_ssm_parameter.gemini_api_key
terraform state rm aws_ssm_parameter.openai_api_key
terraform state rm aws_ssm_parameter.turnstile_secret_key

# Random string (no AWS resource, just local state)
terraform state rm random_string.jwt_secret

# ALB target group + listener rule
terraform state rm aws_alb_target_group.ecs_target
terraform state rm aws_lb_listener_rule.alb_listener_rule_api_http

# ECS service + task def + log group
terraform state rm aws_ecs_service.ecs_service
terraform state rm aws_ecs_task_definition.task_definition
terraform state rm aws_cloudwatch_log_group.ecs_log_group

# S3 + CloudFront + OAC + function + policies
terraform state rm aws_s3_bucket.webapp_bucket
terraform state rm aws_s3_bucket_public_access_block.webapp_bucket_public_access
terraform state rm aws_s3_bucket_policy.webapp_bucket_policy
terraform state rm aws_cloudfront_origin_access_control.webapp_oac
terraform state rm aws_cloudfront_function.spa_routing
terraform state rm aws_cloudfront_distribution.webapp_distribution
terraform state rm aws_cloudfront_cache_policy.api_cache_policy
terraform state rm aws_cloudfront_origin_request_policy.api_origin_request_policy
terraform state rm aws_cloudwatch_log_group.cloudfront_logs

# ACM + Cloudflare DNS
terraform state rm aws_acm_certificate.ssl_cert
for r in $(terraform state list | grep 'cloudflare_record.acm_validation'); do
  terraform state rm "$r"
done
terraform state rm cloudflare_record.root_to_cloudfront
terraform state rm cloudflare_record.www_to_cloudfront
terraform state rm cloudflare_zone_settings_override.ssl_tls_settings
```

Verify platform state is now generic-only:

```bash
terraform state list | sort
```

Expected: VPC, subnets, IGW, route tables, NACLs, security groups, RDS, RDS subnet group, ECS cluster, IAM roles, instance profile, launch config, ASG, EFS (Kafka), Kafka service discovery, Kafka task def, Kafka service, Kafka log group, ALB, HTTP listener, random_strings for db. And the new `/platform/rds/*` SSM params.

## 5. Import resources into protoapp product state

Run from `infra-setup/products/protoapp/`:

```bash
cd ../products/protoapp

# SSM parameters — name = import ID
terraform import aws_ssm_parameter.db_endpoint /db_secrets/protoapp_db_endpoint
terraform import aws_ssm_parameter.db_username /db_secrets/protoapp_db_username
terraform import aws_ssm_parameter.db_password /db_secrets/protoapp_db_password
terraform import aws_ssm_parameter.db_name /db_secrets/protoapp_db_name
terraform import aws_ssm_parameter.jwt_secret /jwt_secrets/protoapp_jwt_secret
terraform import aws_ssm_parameter.google_client_id /google_secrets/protoapp_google_client_id
terraform import aws_ssm_parameter.google_client_secret /google_secrets/protoapp_google_client_secret
terraform import aws_ssm_parameter.google_redirect_uri /google_secrets/protoapp_google_redirect_uri
terraform import aws_ssm_parameter.web_app_uri /api_service/protoapp_web_app_uri
terraform import aws_ssm_parameter.stripe_publishable_key /stripe_secrets/protoapp_stripe_publishable_key
terraform import aws_ssm_parameter.stripe_secret_key /stripe_secrets/protoapp_stripe_secret_key
terraform import aws_ssm_parameter.stripe_webhook_secret /stripe_secrets/protoapp_stripe_webhook_secret
terraform import aws_ssm_parameter.resend_api_key /api_service/protoapp_resend_api_key
terraform import aws_ssm_parameter.default_email_sender_address /api_service/protoapp_default_email_sender_address
terraform import aws_ssm_parameter.gemini_api_key /api_service/protoapp_gemini_api_key
terraform import aws_ssm_parameter.openai_api_key /api_service/protoapp_openai_api_key
terraform import aws_ssm_parameter.turnstile_secret_key /api_service/protoapp_turnstile_secret_key

# ALB target group + listener rule (ARNs from step 3)
terraform import aws_alb_target_group.ecs_target "$TARGET_GROUP_ARN"
terraform import aws_lb_listener_rule.alb_listener_rule_api_http "$LISTENER_RULE_ARN"

# ECS: cluster/service format for service, arn for task def, name for log group
terraform import aws_ecs_service.ecs_service "$ECS_CLUSTER_NAME/api_service"
terraform import aws_ecs_task_definition.task_definition "$TASK_DEF_ARN"
terraform import aws_cloudwatch_log_group.ecs_log_group api-logs

# S3 — bucket name
terraform import aws_s3_bucket.webapp_bucket protoapp.xyz-webapp
terraform import aws_s3_bucket_public_access_block.webapp_bucket_public_access protoapp.xyz-webapp
terraform import aws_s3_bucket_policy.webapp_bucket_policy protoapp.xyz-webapp

# CloudFront
terraform import aws_cloudfront_origin_access_control.webapp_oac "$OAC_ID"
terraform import aws_cloudfront_function.spa_routing "spa-routing-function"
terraform import aws_cloudfront_distribution.webapp_distribution "$CLOUDFRONT_ID"
terraform import aws_cloudfront_cache_policy.api_cache_policy "$CACHE_POLICY_ID"
terraform import aws_cloudfront_origin_request_policy.api_origin_request_policy "$ORIGIN_REQ_POLICY_ID"
terraform import aws_cloudwatch_log_group.cloudfront_logs /aws/cloudfront/webapp

# ACM cert
terraform import aws_acm_certificate.ssl_cert "$ACM_CERT_ARN"

# Cloudflare records (format: zone_id/record_id)
terraform import cloudflare_record.root_to_cloudfront "$CF_ZONE_ID/$CF_ROOT_RECORD_ID"
terraform import cloudflare_record.www_to_cloudfront "$CF_ZONE_ID/$CF_WWW_RECORD_ID"
terraform import cloudflare_zone_settings_override.ssl_tls_settings "$CF_ZONE_ID"

# ACM validation Cloudflare records — for_each keyed by SAN domain name
# Find them first:
#   aws acm describe-certificate --certificate-arn "$ACM_CERT_ARN" --query 'Certificate.DomainValidationOptions'
# Then per SAN (e.g., "*.protoapp.xyz" and "www.protoapp.xyz"):
# terraform import 'cloudflare_record.acm_validation["*.protoapp.xyz"]' "$CF_ZONE_ID/<record-id>"
# terraform import 'cloudflare_record.acm_validation["www.protoapp.xyz"]' "$CF_ZONE_ID/<record-id>"
```

## 6. Verify — both `terraform plan` should show zero changes

```bash
cd infra-setup/platform
terraform plan   # expect: "No changes"

cd ../products/protoapp
terraform plan   # expect: "No changes"
```

If platform plan shows destroys, some state rm was missed. Re-run missed removals.
If protoapp plan shows creates, some import was missed. Re-run missed imports.
If plan shows modifications, the code doesn't exactly match existing AWS state — compare and adjust code to match what's actually deployed.

## 7. (Optional) Clean up orphaned old-path SSM params later

After migration and after products fully switch to `/platform/rds/*` paths, the old `/db_secrets/protoapp_*` SSM params become redundant. Delete manually with `aws ssm delete-parameter` when convenient.

## Future: add launchcamp

`products/launchcamp/` will be its own state (bucket `launchcamp-terraform-state`), created as a copy of `products/protoapp/` with:
- `variables.tf`: `product = "launchcamp"`, `domain_name = "launchcamp.xyz"`, new `cloudflare_zone_id`
- SSM paths flattened to `/launchcamp/*` (no legacy compat needed for a fresh product)
- ALB listener rule priority 100 with `X-Product-Id = "launchcamp"` condition
- CloudFront distribution with custom origin header `X-Product-Id: launchcamp`

When launchcamp is introduced, protoapp's listener rule also needs a small update:
- Lower priority from 1 to 1000
- Add `X-Product-Id = "protoapp"` condition
- Add matching `X-Product-Id: protoapp` custom header to protoapp's CloudFront origin

These are paired changes in `products/protoapp/` (alb-routing.tf + s3-cloudfront.tf) and can go in the launchcamp-adds PR.
