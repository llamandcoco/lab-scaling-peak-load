include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  root_vars = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  common    = read_terragrunt_config(find_in_parent_folders("_env_common.hcl")).locals
  env       = local.root_vars.env
  app       = local.root_vars.app
}

terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/ecr?ref=${local.common.ecr_ref}"
}

inputs = {
  repository_name    = "${local.env}-${local.app}-registry"
  scan_on_push       = true
  image_tag_mutability = "IMMUTABLE"
  force_delete       = true
  tags = {
    Environment = local.env
    Application = local.app
  }
}
