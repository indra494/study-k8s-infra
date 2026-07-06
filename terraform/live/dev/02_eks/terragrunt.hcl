include "root" {
  path = find_in_parent_folders()
}

locals {
  root_vars = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
  env_vars  = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

# VPC 모듈 배포가 완료되었는지 확인하고 그 output을 가져옴
dependency "vpc" {
  config_path = "../01_vpc"
}

terraform {
  source = "../../../modules/02_eks"
}

inputs = {
  # VPC 모듈의 outputs에서 서브넷 ID를 자동으로 가져옴
  subnet_ids  = dependency.vpc.outputs.private_subnets
  vpc_id      = dependency.vpc.outputs.vpc_id
  cluster_name     = "${local.root_vars.inputs.project_name}-${local.env_vars.inputs.env}-eks"
}