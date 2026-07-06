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

dependency "eks" {
  config_path = "../02_eks"
}

terraform {
  source = "../../../modules/05_rds"
}

inputs = {
  name            = "${local.root_vars.inputs.project_name}-${local.env_vars.inputs.env}-rds"
  vpc_id          = dependency.vpc.outputs.vpc_id
  private_subnets = dependency.vpc.outputs.private_subnets
  eks_node_sg_id  = dependency.eks.outputs.node_security_group_id
}