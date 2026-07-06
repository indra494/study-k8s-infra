# live의 terragrunt.hcl에서 미리 조합해서 넘겨주는 리소스 이름
variable "name" { type = string }

# RDS 모듈 고유 입력 변수
variable "vpc_id" { type = string }
variable "private_subnets" { type = list(string) }
variable "eks_node_sg_id" { type = string }