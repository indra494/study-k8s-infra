resource "aws_security_group" "bastion_sg" {
  name        = "${var.name}-sg"
  description = "SSM bastion - no inbound ports, SSM Session Manager only"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# bastion에서 RDS(3306)로 나가는 트래픽을 RDS 보안그룹에서 허용
resource "aws_security_group_rule" "bastion_to_rds" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = var.rds_security_group_id
  source_security_group_id = aws_security_group.bastion_sg.id
}
