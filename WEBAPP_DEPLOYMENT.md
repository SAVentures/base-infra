# Webapp Deployment Guide

The webapp is a static Vite app served by S3 + CloudFront (per product, provisioned by `modules/product`), with `/api/*` forwarded to the shared ALB.

## Architecture

```
Internet → Cloudflare DNS → CloudFront (per product) ─┬─→ S3 (static assets)
                                                      └─→ Shared ALB (X-Product-Id header) → ECS service
```

## Build-time environment variables

Vite embeds these at build time, so they must match the product's domain and Cloudflare/Google/Stripe/Turnstile registrations.

Both products need a rebuild after 2026-07-25: meerkat moved to a new domain,
and both got new Google OAuth clients. A stale bundle points at a host that no
longer resolves.

**meerkat** (`protoapp-meerkat-webapp`, distribution `E29P2UU1UDEGD0`):

```
VITE_API_URL=https://meerkat.protoapp.xyz
VITE_GOOGLE_CLIENT_ID=457623122746-psfkemqv8hves5lkquepma8sng9paa7c.apps.googleusercontent.com
VITE_GOOGLE_REDIRECT_URL=https://meerkat.protoapp.xyz/api/auth/google/callback
```

**sjocamp** (`app.sjocamp.co-webapp`, distribution `E2FFC4WVGBFGG3`):

```
VITE_API_URL=https://app.sjocamp.co
VITE_GOOGLE_CLIENT_ID=457623122746-4jpfr3n9dhbnrjoq7a48nt5c60psdo90.apps.googleusercontent.com
VITE_GOOGLE_REDIRECT_URL=https://app.sjocamp.co/api/auth/google/callback
```

Shared by both (account-wide, from `/platform/*`):

```
VITE_STRIPE_PUBLISHABLE_KEY=pk_live_51PxCuHP3M2g0n0x3rpcflZx5JgmeMo7Le4eQFEj2coL6EwODaZ4L0YsfUGm32hXjzMruRZtmQXqUlvHcz2ZsVCwZ00O8C2Is5h
VITE_TURNSTILE_SITE_KEY=0x4AAAAAACI80A46LKnXUKgs
```

Every value above is public by design — it ships inside the built bundle.
Do not put `google_client_secret` or any `sk_`/`whsec_` value in a Vite
variable; those are server-side only and reach the API as ECS environment
variables.

## Deploy commands

Read ids from the product's SSM manifest rather than hardcoding them — that is
what the manifest exists for.

```bash
PRODUCT=meerkat   # or sjocamp
MANIFEST=$(aws ssm get-parameter --name "/$PRODUCT/manifest" --query 'Parameter.Value' --output text)
BUCKET=$(echo "$MANIFEST" | jq -r '.aws.webappS3Bucket')
DIST=$(echo "$MANIFEST" | jq -r '.aws.cloudfrontDistributionId')

aws s3 sync ./dist "s3://$BUCKET/" --delete
aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/*"
```

## CI/CD

The workflow at `.github/workflows/webapp.yml` handles push-to-main builds. It still has protoapp values hardcoded (legacy) and should be reworked to read the SSM manifest as shown above.

## SPA routing

CloudFront Function `${product}-spa-routing` rewrites non-asset, non-API paths to `/index.html` so TanStack Router handles client-side routes. No 404 configuration needed.
