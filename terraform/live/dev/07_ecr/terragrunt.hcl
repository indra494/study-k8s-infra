include "root" {
  path = find_in_parent_folders()
}

locals {
  root_vars = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
  env_vars  = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "../../../modules/07_ecr"
}

inputs = {
  name_prefix = "${local.root_vars.inputs.project_name}-${local.env_vars.inputs.env}"
}
