# Webapp Deployment Guide

The webapp is a static Vite app served by S3 + CloudFront (per product, provisioned by `modules/product`), with `/api/*` forwarded to the shared ALB.

## Architecture

```
Internet → Cloudflare DNS → CloudFront (per product) ─┬─→ S3 (static assets)
                                                      └─→ Shared ALB (X-Product-Id header) → ECS service
```

## Build-time environment variables

Vite embeds these at build time, so they must match the product's domain and Cloudflare/Google/Stripe/Turnstile registrations.

For **sjocamp**:

```
VITE_GOOGLE_CLIENT_ID=<sjocamp google oauth client id>
VITE_GOOGLE_REDIRECT_URL=https://sjocamp.co/api/auth/google/callback
VITE_API_URL=https://sjocamp.co
VITE_STRIPE_PUBLISHABLE_KEY=<pk_live_...>
VITE_TURNSTILE_SITE_KEY=<sjocamp turnstile site key>
```

## Deploy commands

Read ids from the product's SSM manifest rather than hardcoding them — that is
what the manifest exists for.

```bash
PRODUCT=protoapp   # or sjocamp
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
