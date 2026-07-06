include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules/08_github_oidc"
}

inputs = {
  github_org = "indra494"
  repo_names = ["study-k8s-engame-api", "study-k8s-engame-front", "study-k8s-infra"]
}
