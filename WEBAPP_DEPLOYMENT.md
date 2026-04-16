# Webapp Deployment Guide

The webapp is a static Vite app served by S3 + CloudFront (per product), with `/api/*` forwarded to the shared ALB.

## Architecture

```
Internet → Cloudflare DNS → CloudFront (per product) ─┬─→ S3 (static assets)
                                                      └─→ Shared ALB (X-Product-Id header) → ECS service
```

## Build-time environment variables

Vite embeds these at build time, so they must match the product's domain and Cloudflare/Google/Stripe/Turnstile registrations.

For **launchcamp**:

```
VITE_GOOGLE_CLIENT_ID=<launchcamp google oauth client id>
VITE_GOOGLE_REDIRECT_URL=https://launchcamp.xyz/api/auth/google/callback
VITE_API_URL=https://launchcamp.xyz
VITE_STRIPE_PUBLISHABLE_KEY=<pk_live_...>
VITE_TURNSTILE_SITE_KEY=<launchcamp turnstile site key>
```

## Deploy commands

```bash
cd webapp
npm ci
# (env vars as above)
npm run build

aws s3 sync ./dist s3://launchcamp.xyz-webapp/ --delete
aws cloudfront create-invalidation --distribution-id <cloudfront-id> --paths "/*"
```

`<cloudfront-id>` comes from `terraform -chdir=../infra-setup/products/launchcamp output -raw cloudfront_distribution_id`.

## CI/CD

The workflow at `.github/workflows/webapp.yml` handles push-to-main builds. It currently has protoapp values hardcoded (legacy). PR 2 will parameterize it to target launchcamp.

## SPA routing

CloudFront Function `${product}-spa-routing` rewrites non-asset, non-API paths to `/index.html` so TanStack Router handles client-side routes. No 404 configuration needed.
