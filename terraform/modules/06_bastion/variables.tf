variable "name" { type = string }

variable "vpc_id" { type = string }
variable "private_subnets" { type = list(string) }

# RDS 보안그룹 ID - bastion에서 RDS로 붙는 ingress 규칙을 여기서 추가해줌
variable "rds_security_group_id" { type = string }
