output "db_instance_endpoint" {
  value = aws_db_instance.rds_main.endpoint
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}

output "security_group_id" {
  value = aws_security_group.rds_sg.id
}
