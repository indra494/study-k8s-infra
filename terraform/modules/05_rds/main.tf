resource "random_password" "db" {
  length  = 20
  special = false
}

resource "aws_db_instance" "rds_main" {
  identifier             = var.name
  db_name                = "usb_db"
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  username               = "admin"
  password               = random_password.db.result

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet.name
  skip_final_snapshot    = true
}

resource "aws_db_subnet_group" "rds_subnet" {
  name       = "${var.name}-subnet-group"
  subnet_ids = var.private_subnets
}