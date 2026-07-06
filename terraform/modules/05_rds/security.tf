resource "aws_security_group" "rds_sg" {
  name        = "${var.name}-sg"
  description = "Security group for RDS instance"
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "eks_to_rds" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_sg.id
  source_security_group_id = var.eks_node_sg_id
}