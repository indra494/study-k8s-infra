include "root" {
  path = find_in_parent_folders()
}

dependency "eks" {
  config_path = "../02_eks"
}

terraform {
  source = "../../../modules/04_eks_lb_controller"
}

inputs = {
  oidc_provider_url = dependency.eks.outputs.oidc_provider_url
}