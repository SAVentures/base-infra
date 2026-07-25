# A child module resolves provider source addresses from its own
# required_providers block. Without cloudflare declared here, Terraform assumes
# hashicorp/cloudflare and init fails — in this module standalone and in every
# root stack that consumes it, regardless of what the root declares.
terraform {
  required_version = ">= 1.2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}
