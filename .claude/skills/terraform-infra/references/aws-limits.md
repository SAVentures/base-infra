# AWS quotas that shape Terraform designs

Verified against AWS docs, July 2026. Quotas change — re-check before betting an
architecture on a number:

```bash
aws elbv2 describe-account-limits --region us-east-1
aws service-quotas list-service-quotas --service-code cloudfront
```

## Application Load Balancer

| Quota | Default | Adjustable |
|---|---|---|
| **Target groups per ALB** | **100** | **No** |
| Rules per ALB (excluding default) | 100 | Yes |
| Condition values per rule | 5 | No |
| Match evaluations per rule | 5 | No |
| Target groups per action | 5 | No |
| Listeners per ALB | 50 | Yes |
| ALBs per region | 50 | Yes |
| Target groups per region | 3,000 (shared with NLB) | Yes |
| Load balancers per target group | 1 | No |

**The binding constraint for a shared ALB is target groups per ALB (100, not
adjustable), not the rules quota.** Rules are adjustable; target groups are not.
If each service needs its own target group, ~100 services is a hard wall, and the
fix is another load balancer rather than a support ticket.

Note the rules quota is **per load balancer**, not per listener.

### Routing many services through one ALB

- **Header match** (e.g. an `X-Product-Id` injected by each CloudFront
  distribution). Survives a hostname change — worth it if services will move
  domains later.
- **Host header match.** Self-documenting, no injection needed, but every rule
  must be edited when a service changes domain.

Either way, make the listener default an explicit `fixed_response` 404. **A rule
with no distinguishing condition is a catch-all and will silently absorb traffic
meant for other services — including into another service's database.** Every
service should match on something positive.

Rule priorities are unique integers evaluated low to high; AWS rejects
duplicates. Allocate in blocks (100, 200, 300...) so services can be added
without renumbering.

## CloudFront

| Quota | Default | Adjustable |
|---|---|---|
| Distributions per account | 500 | Yes |
| Alternate domain names (CNAMEs) per distribution | 100 | Yes |
| Cache behaviors per distribution | 75 | Yes |
| Origins per distribution | 100 | Yes |
| **Custom cache policies per account** | **20** | Yes |
| **Custom origin request policies per account** | **20** | Yes |
| Custom response headers policies per account | 20 | Yes |
| **SSL certificates per distribution** | **1** | No |
| Origin access controls per account | 100 | Yes |
| CloudFront Functions per account | 100 | — |
| Distributions per function / cache policy / ORP | 100 | — |
| Custom headers added to origin requests | 30 | Yes |

Three drive design decisions:

**Custom policies cap at 20 per account.** A per-product copy of an identical
cache policy and origin request policy burns the quota fast — two policies per
product means a wall at ten products. These are account-level reusable
resources: define once, reference by ID. Sharing is a scaling requirement, not
just DRY.

**One certificate per distribution.** Serving two hostnames during a migration
needs a single cert covering both. Across different DNS zones that means a
transition certificate validated in both — real work, worth weighing against
simply accepting brief downtime.

**An alternate domain name attaches to only one distribution** account-wide. Two
distributions cannot both claim `app.example.com`. That forces the choice between
one distribution per subdomain, and one distribution with a wildcard alias plus a
function routing on `Host`.

### Wildcard certificates

`*.example.com` covers one label only — `a.example.com`, never
`a.b.example.com`. Deeper nesting needs another SAN.

## Cookies across subdomains

Not a quota, but it shapes multi-tenant subdomain designs and is easy to miss.

If the parent domain is not on the Public Suffix List, a cookie scoped to
`.example.com` is readable **and writable** by every sibling subdomain. Siblings
are not isolated origins for cookie purposes: compromising one lets it forge
sessions for the others.

Fine when every subdomain is equally trusted. Not fine when one is a prototype
and another takes payments. Set session cookies host-only (no `Domain=`) and
treat cross-subdomain SSO as a deliberate design with a central issuer, not a
side effect of cookie scope.

## Public IPv4 addressing

Since February 2024 **every** public IPv4 address is billed hourly, including
ones on running instances and load balancer ENIs. A multi-AZ ALB holds several.
On a small footprint this can rival the compute bill.

## RDS and Savings Plans

Savings Plans do **not** cover RDS — that needs Reserved Instances, bought
separately. Within EC2, an EC2 Instance Savings Plan is size-flexible inside one
instance family and region, so it survives right-sizing within the family; a
Compute Savings Plan is broader (EC2, Fargate, Lambda) at a shallower discount.

Right-size before committing. A commitment sized to a footprint you are about to
shrink pays for capacity you no longer use.
