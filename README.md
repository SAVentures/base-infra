# infra-setup

AWS infrastructure for the launchcamp monorepo, structured as a **shared platform** (the original protoapp stack) + **per-product stacks** (launchcamp and any future products).

## Layout

```
infra-setup/
├── platform/               # shared: VPC, RDS, ECS cluster, ALB, Kafka
│                           # (was the original protoapp stack — reused as-is)
└── products/
    └── launchcamp/         # launchcamp-only: domain, SSM, ECS service, webapp
```

### State storage

- **platform** state: `s3://protoapp-infra-terraform-state/state/terraform.tfstate` (unchanged from the original setup)
- **products/launchcamp** state: `s3://launchcamp-terraform-state/products/launchcamp.tfstate` (fresh bucket)

## How products share the platform

The `platform/` stack exports outputs (ALB ARN, ECS cluster, VPC, subnets, kafka DNS, RDS host) that product stacks read via `terraform_remote_state`. Each product stack then provisions only its own resources on top of those shared foundations.

Routing: each product has its own CloudFront distribution that forwards `/api/*` to the shared ALB with a custom `X-Product-Id` header. A per-product listener rule on the ALB matches that header and forwards to the product's target group. One ALB serves N products without path or host collisions.

## Getting launchcamp live

See [RUNBOOK.md](./RUNBOOK.md) for the end-to-end sequence.

## Adding a new product (future)

1. `cp -r products/launchcamp products/<newproduct>`
2. Edit `products/<newproduct>/variables.tf`: update `product`, `domain_name`, `alb_rule_priority` (must be unique — launchcamp uses 100)
3. Edit `products/<newproduct>/main.tf`: change backend `key` to `products/<newproduct>.tfstate`
4. `terraform init && terraform apply`
5. Create the product's DB + user on shared RDS (see RUNBOOK step 3 for the pattern)
6. Populate `/<newproduct>/*` SSM params

## Shared vs per-product

| Resource | Location | Scoping |
|---|---|---|
| VPC, subnets, NACLs | platform | all products share |
| RDS Postgres instance | platform | one logical DB per product |
| ECS cluster | platform | one service per product |
| ALB | platform | one listener rule + target group per product |
| Kafka broker | platform | one topic prefix per product (`<product>.<topic>`) |
| CloudFront + S3 webapp | product | per-product |
| ACM cert | product | per-product |
| Cloudflare DNS | product | per-product |
| SSM params | both | `/platform/*` for shared infra, `/<product>/*` for each product |
