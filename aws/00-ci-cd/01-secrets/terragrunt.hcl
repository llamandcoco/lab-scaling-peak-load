include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  root_vars = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  common    = read_terragrunt_config(find_in_parent_folders("_env_common.hcl")).locals
  env       = local.root_vars.env
  app       = local.root_vars.app

  # Get GitHub token from environment (loaded by Makefile from .env file)
  github_token = get_env("GITHUB_TOKEN_LAB_SCALING", "")
}

terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/parameter-store?ref=${local.common.parameter_store_ref}"
}

inputs = {
  parameters = {
    "/${local.env}/${local.app}/github-token" = {
      description = "GitHub Personal Access Token for CodePipeline"
      type        = "SecureString"
      value       = local.github_token != "" ? local.github_token : "REPLACE_ME_WITH_ACTUAL_TOKEN"
    }
  }
}
