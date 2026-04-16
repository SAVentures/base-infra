# Runbook

Two stacks in this PR are now applied to AWS:

- `platform/` — shared VPC, RDS, ECS cluster, ALB, Kafka. State at `s3://protoapp-infra-terraform-state/state/terraform.tfstate`.
- `products/protoapp/` — protoapp.xyz live, ECS service, CloudFront, S3, SSM. State at `s3://protoapp-terraform-state/state/terraform.tfstate`.
- `products/launchcamp/` — `app.launchcamp.xyz` SaaS, CloudFront, S3, ECS service `launchcamp-api`, SSM. State at `s3://launchcamp-terraform-state/state/terraform.tfstate`.

The launchcamp landing page (apex `launchcamp.xyz` and `www.launchcamp.xyz`) is intentionally not managed here — it lives on Cloudflare Pages and is untouched.

## Routing model on the shared ALB

| Priority | Match | Target |
|---|---|---|
| 100 | path `/api/*` AND header `X-Product-Id=launchcamp` | launchcamp target group |
| 1000 | path `/api/*` (no header) | protoapp target group |
| default | (any /\* not matched above) | 404 |

Each product's CloudFront origin injects the `X-Product-Id` header so the ALB can dispatch.

## What was done in this PR (already applied)

- Migrated all protoapp-specific resources from the original single-stack into `products/protoapp/` via `terraform state rm` + `terraform import` (zero recreation).
- Upgraded Cloudflare provider to v5 in `products/protoapp/` (cloudflare_record → cloudflare_dns_record, value → content, cloudflare_zone_settings_override → 5x cloudflare_zone_setting).
- Lowered protoapp's ALB listener rule priority from 1 → 1000 to make room for launchcamp at priority 100.
- Created `products/launchcamp/` with state in new bucket `launchcamp-terraform-state`. Applied: ACM cert (validated), Cloudflare DNS for `app.launchcamp.xyz`, S3 bucket `app.launchcamp.xyz-webapp`, CloudFront distribution, ECS service `launchcamp-api`, ALB target group + listener rule, 14 SSM placeholders.

## What's left to make launchcamp actually serve traffic

The ECS service `launchcamp-api` is deployed but tasks are unhealthy until the database exists and SSM secrets hold real values.

### 1. Create the launchcamp database on shared RDS

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=ECS AutoScaling Group" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

RDS_HOST=$(aws ssm get-parameter --name /platform/rds/host --query Parameter.Value --output text)
RDS_MASTER_USER=$(aws ssm get-parameter --name /platform/rds/master_username --with-decryption --query Parameter.Value --output text)
RDS_MASTER_PASS=$(aws ssm get-parameter --name /platform/rds/master_password --with-decryption --query Parameter.Value --output text)

# Port-forward (blocks; run in a separate terminal)
aws ssm start-session --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$RDS_HOST\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"15432\"]}"
```

Then in another terminal:

```bash
LAUNCHCAMP_APP_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)

PGPASSWORD="$RDS_MASTER_PASS" psql -h localhost -p 15432 -U "$RDS_MASTER_USER" -d postgres <<EOF
CREATE DATABASE launchcamp;
CREATE USER launchcamp_app WITH PASSWORD '$LAUNCHCAMP_APP_PASS';
GRANT ALL PRIVILEGES ON DATABASE launchcamp TO launchcamp_app;
EOF

aws ssm put-parameter --name /launchcamp/db_username --type SecureString --value launchcamp_app --overwrite
aws ssm put-parameter --name /launchcamp/db_password --type SecureString --value "$LAUNCHCAMP_APP_PASS" --overwrite
```

Stop the port-forward when done. Run Flyway migrations from the base-server repo against this new DB.

### 2. Register external services for launchcamp

- **Google Cloud Console**: new OAuth client. Authorized redirect URI: `https://app.launchcamp.xyz/api/auth/google/callback`. Capture client_id + client_secret.
- **Stripe**: live-mode keys. Webhook endpoint: `https://app.launchcamp.xyz/api/webhooks/stripe` (path may differ — match your handler). Capture publishable_key + secret_key + webhook signing secret.
- **Resend**: verify `launchcamp.xyz` as a sending domain (DKIM + SPF TXT records on the apex zone). Reuse existing API key or generate a new one.
- **Turnstile**: new site for `app.launchcamp.xyz`. Capture site_key + secret.

### 3. Populate launchcamp SSM params

```bash
aws ssm put-parameter --name /launchcamp/jwt_secret --type SecureString --value "$(openssl rand -hex 32)" --overwrite
aws ssm put-parameter --name /launchcamp/google_client_id --type String --value "<id>" --overwrite
aws ssm put-parameter --name /launchcamp/google_client_secret --type SecureString --value "<secret>" --overwrite
aws ssm put-parameter --name /launchcamp/stripe_publishable_key --type String --value "<pk_live_...>" --overwrite
aws ssm put-parameter --name /launchcamp/stripe_secret_key --type SecureString --value "<sk_live_...>" --overwrite
aws ssm put-parameter --name /launchcamp/stripe_webhook_secret --type SecureString --value "<whsec_...>" --overwrite
aws ssm put-parameter --name /launchcamp/resend_api_key --type SecureString --value "<re_...>" --overwrite
aws ssm put-parameter --name /launchcamp/default_email_sender_address --type String --value "no-reply@launchcamp.xyz" --overwrite
aws ssm put-parameter --name /launchcamp/gemini_api_key --type SecureString --value "<key>" --overwrite
aws ssm put-parameter --name /launchcamp/openai_api_key --type SecureString --value "<key>" --overwrite
aws ssm put-parameter --name /launchcamp/turnstile_site_key --type String --value "<site key>" --overwrite
aws ssm put-parameter --name /launchcamp/turnstile_secret_key --type SecureString --value "<secret>" --overwrite
```

### 4. Force a new ECS deployment so tasks pick up the new env

```bash
aws ecs update-service --cluster ecs-cluster --service launchcamp-api --force-new-deployment
```

Tasks will pull the latest task definition, read SSM at boot, and (assuming DB + secrets are right) become healthy.

### 5. Deploy the webapp

The webapp pipeline at `.github/workflows/webapp.yml` still targets protoapp's S3 bucket and env vars. Either:
- Update the workflow in PR 2 to target `app.launchcamp.xyz-webapp` and the launchcamp env vars, OR
- Manually deploy once:

```bash
cd webapp
npm ci
VITE_GOOGLE_CLIENT_ID=<launchcamp client id> \
VITE_GOOGLE_REDIRECT_URL=https://app.launchcamp.xyz/api/auth/google/callback \
VITE_API_URL=https://app.launchcamp.xyz \
VITE_STRIPE_PUBLISHABLE_KEY=<pk_live_...> \
VITE_TURNSTILE_SITE_KEY=<site key> \
npm run build

aws s3 sync ./dist s3://app.launchcamp.xyz-webapp/ --delete
aws cloudfront create-invalidation \
  --distribution-id $(terraform -chdir=infra-setup/products/launchcamp output -raw cloudfront_distribution_id) \
  --paths "/*"
```

### 6. Smoke test

1. Visit `https://app.launchcamp.xyz` — SPA loads.
2. Sign up with email; confirm email arrives from Resend.
3. Log in with Google — OAuth completes.
4. Hit a Stripe checkout flow — small live charge, refund after.
5. Tail API logs: `aws logs tail /launchcamp/api --follow`.
6. Tail Kafka consumer if applicable: tasks publish to `launchcamp.webhook-events` topic.

## Adding the next product later

Copy `products/launchcamp/` → `products/<newproduct>/`. In the new directory:

1. `variables.tf`: change `product`, `domain_name`, `cloudflare_zone_id`, `alb_rule_priority` (must be unique — protoapp=1000, launchcamp=100; pick e.g. 200)
2. `main.tf`: change backend bucket to `<newproduct>-terraform-state` (create the bucket first)
3. `terraform init && terraform apply`
4. Run steps 1–6 above with `<newproduct>` in place of `launchcamp`

The pattern scales — each product is fully isolated in code and state, and shares only the platform's VPC/RDS/ECS/ALB/Kafka.
