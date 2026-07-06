resource "aws_secretsmanager_secret" "db" {
  name = "${var.name}-credentials"
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = aws_db_instance.rds_main.username
    password = random_password.db.result
    host     = aws_db_instance.rds_main.address
    port     = aws_db_instance.rds_main.port
    dbname   = aws_db_instance.rds_main.db_name
  })
}
