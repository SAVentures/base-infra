resource "aws_db_instance" "default" {
  identifier              = "my-postgres-db"
  engine                  = "postgres"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_type            = "gp3"
  backup_retention_period = 1
  username                = random_string.db_username.result
  password                = random_string.db_password.result
  db_subnet_group_name    = aws_db_subnet_group.my_subnet_group.name

  vpc_security_group_ids = [aws_security_group.postgres.id]

  skip_final_snapshot = true
}

output "db_instance_endpoint" {
  value = aws_db_instance.default.endpoint
}
