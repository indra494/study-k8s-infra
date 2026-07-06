include "root" {
  path = find_in_parent_folders()
}

locals {
  root_vars = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
  env_vars  = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

dependency "vpc" {
  config_path = "../01_vpc"
}

dependency "rds" {
  config_path = "../05_rds"
}

terraform {
  source = "../../../modules/06_bastion"
}

inputs = {
  name                   = "${local.root_vars.inputs.project_name}-${local.env_vars.inputs.env}-bastion"
  vpc_id                 = dependency.vpc.outputs.vpc_id
  private_subnets        = dependency.vpc.outputs.private_subnets
  rds_security_group_id  = dependency.rds.outputs.security_group_id
}
