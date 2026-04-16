# Runbook: bring up launchcamp prod on AWS

Approach: **keep the existing protoapp infrastructure running** as the shared platform (VPC, RDS, ECS cluster, shared ALB, Kafka). ADD launchcamp-specific resources in a new state (ACM, CloudFront, S3, ECS service, target group, listener rule, Cloudflare DNS, `/launchcamp/*` SSM params). Nothing gets destroyed except at your discretion in step 9.

## 0. Prerequisites

- AWS CLI authenticated as admin of account `339713122183`
- Terraform >= 1.2
- Cloudflare zone for `launchcamp.xyz` exists; you know its zone ID
- `/cloudflare/api_key` SSM param already exists in us-east-1
- `gh` CLI authenticated as protoappxyz

## 1. Create the new Terraform state bucket

Platform state stays in `protoapp-infra-terraform-state`. Launchcamp (and future products) get a separate bucket.

```bash
aws s3api create-bucket --bucket launchcamp-terraform-state --region us-east-1
aws s3api put-bucket-versioning --bucket launchcamp-terraform-state --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket launchcamp-terraform-state \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

## 2. Apply the additive platform changes

This adds new outputs and `/platform/rds/*` SSM params. Nothing existing is touched.

```bash
cd infra-setup/platform
terraform init
terraform plan   # expect ~5 ADD, 0 CHANGE, 0 DESTROY
terraform apply
```

If the plan shows any destroys or changes, stop and investigate — something unexpected drifted.

## 3. Create the launchcamp database on the shared RDS

RDS isn't publicly accessible. Tunnel through an existing ECS node via Session Manager.

```bash
# Find the ECS node instance id
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=ECS AutoScaling Group" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

# Pull RDS host + master creds from SSM
RDS_HOST=$(aws ssm get-parameter --name /platform/rds/host --query Parameter.Value --output text)
RDS_MASTER_USER=$(aws ssm get-parameter --name /platform/rds/master_username --with-decryption --query Parameter.Value --output text)
RDS_MASTER_PASS=$(aws ssm get-parameter --name /platform/rds/master_password --with-decryption --query Parameter.Value --output text)

# Start a port-forwarding session (blocks; run in a separate terminal)
aws ssm start-session --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$RDS_HOST\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"15432\"]}"
```

In another terminal, create the DB + app user:

```bash
LAUNCHCAMP_APP_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)

PGPASSWORD="$RDS_MASTER_PASS" psql -h localhost -p 15432 -U "$RDS_MASTER_USER" -d postgres <<EOF
CREATE DATABASE launchcamp;
CREATE USER launchcamp_app WITH PASSWORD '$LAUNCHCAMP_APP_PASS';
GRANT ALL PRIVILEGES ON DATABASE launchcamp TO launchcamp_app;
EOF

# Stash app creds in SSM (overwrites PLACEHOLDER once product stack applies)
aws ssm put-parameter --name /launchcamp/db_username --type SecureString --value launchcamp_app --overwrite
aws ssm put-parameter --name /launchcamp/db_password --type SecureString --value "$LAUNCHCAMP_APP_PASS" --overwrite
```

Close the port-forwarding session when done.

## 4. Populate the rest of the launchcamp SSM params

External services you register first:
- **Google Cloud Console**: new OAuth client, redirect URI `https://launchcamp.xyz/api/auth/google/callback`
- **Stripe**: live-mode keys, webhook endpoint `https://launchcamp.xyz/api/webhooks/stripe`
- **Resend**: verify `launchcamp.xyz` (add DKIM + SPF TXT in Cloudflare)
- **Turnstile**: new site for launchcamp.xyz

Then:

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

## 5. Deal with the ALB listener rule conflict

The existing shared ALB has a single listener rule at priority 1 that forwards **all** `/api/*` traffic to the protoapp target group — regardless of any header. Launchcamp's listener rule can't beat it.

Pick one:

**Option A (recommended): lower the existing rule's priority.** Edit `infra-setup/platform/alb.tf`, change `priority = 1` to `priority = 1000` on the `aws_lb_listener_rule.alb_listener_rule_api_http` resource, then:

```bash
cd infra-setup/platform
terraform apply   # shows 1 change, the priority update
```

After this, launchcamp's rule (priority 100) evaluates first; protoapp's rule at 1000 catches any fallback.

**Option B: remove the rule entirely.** Delete the `aws_lb_listener_rule.alb_listener_rule_api_http` block from `platform/alb.tf`. `terraform apply` destroys just that rule. Protoapp's target group still exists but receives no ALB traffic.

Either is reversible. Pick A for maximum safety.

## 6. Apply the launchcamp product stack

```bash
cd infra-setup/products/launchcamp
cp terraform.tfvars.example terraform.tfvars
# Edit: set cloudflare_email and cloudflare_zone_id for launchcamp.xyz

terraform init
terraform plan    # expect additions only: ACM cert, CloudFront, S3, target group, listener rule, ECS service, SSM, DNS
terraform apply
```

ACM validation (the `cloudflare_record.acm_validation` resources) can take a few minutes to propagate before the cert reaches `ISSUED` state. `terraform apply` waits on this automatically.

## 7. Deploy the application

**API:**

```bash
docker build -t base-server ./base-server
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 339713122183.dkr.ecr.us-east-1.amazonaws.com
docker tag base-server:latest 339713122183.dkr.ecr.us-east-1.amazonaws.com/base-server:latest
docker push 339713122183.dkr.ecr.us-east-1.amazonaws.com/base-server:latest

aws ecs update-service --cluster ecs-cluster --service launchcamp-api --force-new-deployment
```

The existing `.github/workflows/base-server.yml` still targets the legacy protoapp ECS service (`api_service`). **PR 2** updates it to target `launchcamp-api`.

**Webapp:**

```bash
cd webapp
npm ci
VITE_GOOGLE_CLIENT_ID=<launchcamp client id> \
VITE_GOOGLE_REDIRECT_URL=https://launchcamp.xyz/api/auth/google/callback \
VITE_API_URL=https://launchcamp.xyz \
VITE_STRIPE_PUBLISHABLE_KEY=<pk_live_...> \
VITE_TURNSTILE_SITE_KEY=<site key> \
npm run build

aws s3 sync ./dist s3://launchcamp.xyz-webapp/ --delete
aws cloudfront create-invalidation \
  --distribution-id $(terraform -chdir=infra-setup/products/launchcamp output -raw cloudfront_distribution_id) \
  --paths "/*"
```

## 8. Smoke test launchcamp

1. Visit `https://launchcamp.xyz` — SPA loads.
2. Sign up with email, verify email arrives from Resend.
3. Log in with Google — OAuth redirect succeeds.
4. Stripe checkout — live card, small amount, refund after.
5. Tail API logs: `aws logs tail /launchcamp/api --follow`.

## 9. Later: decommission protoapp

When you're ready to reuse protoapp.xyz for a different product (or retire it), tear down protoapp-specific resources without touching the platform. You can do this file-by-file:

- `aws_s3_bucket.webapp_bucket` (in `platform/s3-cloudfront.tf`) → remove block, apply
- `aws_cloudfront_distribution.webapp_distribution` → remove, apply
- `aws_acm_certificate.ssl_cert` (in `platform/domain.tf`) → remove, apply
- Cloudflare DNS records for protoapp.xyz → remove
- `aws_ecs_service.ecs_service` and `aws_ecs_task_definition.task_definition` (in `platform/api-service.tf`) → remove
- `aws_alb_target_group.ecs_target` and the listener rule → remove
- All `aws_ssm_parameter.*` with `protoapp_` prefix names → remove

Everything else (VPC, RDS, ECS cluster, ALB listener, Kafka, IAM roles) stays, since these are now the shared platform for launchcamp and any future products.
