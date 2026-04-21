# Platform-level SSM params used by product stacks (generic names, no product prefix).
# These mirror the existing protoapp-prefixed params but with product-neutral paths
# so additional products can share the same RDS / platform resources.
#
# Additive only — existing protoapp_* params in secrets.tf are left untouched.

resource "aws_ssm_parameter" "platform_rds_host" {
  name  = "/platform/rds/host"
  type  = "String"
  value = aws_db_instance.default.address
}

resource "aws_ssm_parameter" "platform_rds_endpoint" {
  name  = "/platform/rds/endpoint"
  type  = "String"
  value = aws_db_instance.default.endpoint
}

resource "aws_ssm_parameter" "platform_rds_port" {
  name  = "/platform/rds/port"
  type  = "String"
  value = aws_db_instance.default.port
}

resource "aws_ssm_parameter" "platform_rds_master_username" {
  name  = "/platform/rds/master_username"
  type  = "SecureString"
  value = aws_db_instance.default.username
}

resource "aws_ssm_parameter" "platform_rds_master_password" {
  name  = "/platform/rds/master_password"
  type  = "SecureString"
  value = aws_db_instance.default.password
}
