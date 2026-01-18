include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "codebuild" {
  config_path = "../03-codebuild"
}

locals {
  root_vars = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  common    = read_terragrunt_config(find_in_parent_folders("_env_common.hcl")).locals
  env       = local.root_vars.env
  app       = local.root_vars.app
}

terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/codepipeline?ref=${local.common.codepipeline_ref}"
}
inputs = {
  pipeline_name           = "${local.env}-${local.app}-pipeline"
  env                     = local.env
  app                     = local.app
  github_owner            = "llamandcoco"
  github_repo             = "lab-scaling-peak-load"
  github_branch           = "dev"
  codebuild_project_name  = dependency.codebuild.outputs.project_name
  codebuild_project_arn   = dependency.codebuild.outputs.project_arn

  tags = {
    Environment = local.env
    Application = local.app
    Purpose     = "CI/CD for Docker builds"
  }
}
