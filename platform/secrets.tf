# Generators for the shared RDS master credentials. The generated values feed
# aws_db_instance.default in db.tf and are published to /platform/rds/* in
# platform-ssm.tf for product stacks to consume.

resource "random_string" "db_username" {
  length           = 16
  special          = false
  upper            = false
  override_special = "_"
  numeric          = false
}

resource "random_string" "db_password" {
  length  = 16
  special = false
}
