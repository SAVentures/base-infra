# Secret values are not maintained here. They live SOPS-encrypted in the
# env-registry repo and are rendered into each product's gitignored
# secrets.auto.tfvars, so a value is entered once and reaches both local dev
# and Terraform.
#
#   make secrets PRODUCT=orca      regenerate one product's tfvars
#   make check-secrets PRODUCT=orca  report drift without writing
#
# Requires the env-registry checkout (found by marker file, like the product
# repos' sync script) and the age key at
# ~/Library/Application Support/sops/age/keys.txt

REGISTRY ?= $(firstword $(wildcard ../env-registry ../dev-ports))
PRODUCT  ?=

.PHONY: secrets check-secrets

secrets:
	@test -n "$(PRODUCT)" || { echo "usage: make secrets PRODUCT=<slug>"; exit 2; }
	@test -n "$(REGISTRY)" || { echo "env-registry checkout not found beside this repo"; exit 2; }
	@$(REGISTRY)/render-tfvars $(PRODUCT) > products/$(PRODUCT)/secrets.auto.tfvars
	@echo "wrote products/$(PRODUCT)/secrets.auto.tfvars from $(REGISTRY)"

check-secrets:
	@test -n "$(PRODUCT)" || { echo "usage: make check-secrets PRODUCT=<slug>"; exit 2; }
	@test -n "$(REGISTRY)" || { echo "env-registry checkout not found beside this repo"; exit 2; }
	@$(REGISTRY)/render-tfvars $(PRODUCT) --check products/$(PRODUCT)/secrets.auto.tfvars
