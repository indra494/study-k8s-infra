include "root" {
  path = find_in_parent_folders()
}

locals {
  # 1. 루트의 project_name 가져오기
  root_vars = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
  # 2. env.hcl의 env 가져오기
  env_vars  = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "../../../modules/01_vpc"
}

inputs = {
  # 루트와 환경 파일에서 명확하게 값을 가져와 조합 (에러 없음)
  name = "${local.root_vars.inputs.project_name}-${local.env_vars.inputs.env}-vpc"

  cidr            = "10.0.0.0/16"
  azs             = ["ap-northeast-2a", "ap-northeast-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
}