# infra-setup

AWS infrastructure split into a shared platform stack and one Terraform stack per product. The split lets multiple products share one AWS account — one RDS, one ECS cluster, one ALB — without duplicating cost per product.

## Layout

```
infra-setup/
├── platform/               # shared: VPC, RDS, ECS cluster, ALB, Kafka, IAM
└── products/
    └── protoapp/           # protoapp-only: S3, CloudFront, ACM, ECS service, SSM, DNS
```

### State

- **platform** state: `s3://protoapp-infra-terraform-state/state/terraform.tfstate` (unchanged from the pre-split setup)
- **products/protoapp** state: `s3://protoapp-terraform-state/state/terraform.tfstate` (fresh bucket)

Future products get their own state bucket and live in `products/<name>/`.

## How products share the platform

`platform/` exports outputs (ALB ARN, ECS cluster, VPC, subnets, task role, kafka DNS) that product stacks read via `terraform_remote_state`. Each product stack then provisions only its own resources on top.

Routing (once multiple products exist): each product's CloudFront forwards `/api/*` to the shared ALB with a custom `X-Product-Id` header. A per-product listener rule on the ALB matches that header and forwards to the product's target group. One ALB, N products, no path or host collisions.

## Getting started

See [RUNBOOK.md](./RUNBOOK.md) for the protoapp state migration — how to move existing resources from the pre-split state into platform + products/protoapp without recreating anything.

## Adding a new product (future)

1. `cp -r products/protoapp products/<newproduct>` as a starting template
2. Edit `products/<newproduct>/variables.tf`: set `product`, `domain_name`, `cloudflare_zone_id`
3. Edit `products/<newproduct>/main.tf`: change backend to a new bucket (`<newproduct>-terraform-state`)
4. Change SSM paths in `secrets.tf` to `/<newproduct>/*` (new product, no legacy path compat needed)
5. Add listener rule condition `X-Product-Id = "<newproduct>"` with a unique priority
6. Add matching custom origin header on the product's CloudFront
7. `terraform init && terraform apply`
8. Create the product's DB + user on shared RDS; populate `/<newproduct>/*` SSM

## Shared vs per-product

| Resource | Location |
|---|---|
| VPC, subnets, NACLs | platform |
| RDS Postgres instance | platform (one logical DB per product) |
| ECS cluster | platform (one service per product) |
| ALB | platform (one listener rule + target group per product) |
| Kafka broker | platform (one topic prefix per product) |
| CloudFront + S3 webapp | product |
| ACM cert | product |
| Cloudflare DNS | product |
| SSM params | `/platform/*` for shared infra, per-product paths for each product |
