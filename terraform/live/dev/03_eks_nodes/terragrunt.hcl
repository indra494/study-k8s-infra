include "root" {
  path = find_in_parent_folders()
}

locals {
  root_vars = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
}

# VPC와 EKS 두 곳 모두에 의존성 연결
dependency "vpc" {
  config_path = "../01_vpc"
}

dependency "eks" {
  config_path = "../02_eks"
}

terraform {
  source = "../../../modules/03_eks_nodes"
}

inputs = {
  cluster_name = dependency.eks.outputs.cluster_name
  subnet_ids   = dependency.vpc.outputs.private_subnets
}