include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals { 
  root_vars      = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  env            = local.root_vars.env
  app            = local.root_vars.app
  common         = read_terragrunt_config(find_in_parent_folders("_env_common.hcl")).locals
  aws_account_id = run_cmd("aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text")
  github_token   = get_env("GITHUB_TOKEN_LAB_SCALING", "")
}

terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/codebuild?ref=${local.common.codebuild_ref}"
}

dependencies {
  paths = ["../02-ecr"]
}


inputs = {
  project_name        = "${local.env}-${local.app}-build"
  github_location     = "https://github.com/llamandcoco/lab-scaling-peak-load.git"
  github_branch       = "dev"
  github_webhook      = false  # CodePipeline에서 관리
  github_token        = local.github_token
  buildspec_path      = "buildspec.yml"
  ecr_repository_name = "${local.env}-${local.app}-registry"

  enable_artifact_bucket_access = true
  artifact_bucket_arn           = "arn:aws:s3:::${local.env}-${local.app}-artifacts-${local.aws_account_id}"

  aws_account_id      = local.aws_account_id
  compute_type        = "BUILD_GENERAL1_SMALL"
  image               = "aws/codebuild/standard:7.0"
  privileged_mode     = true
  logs_retention_days = 7

  tags = {
    Environment = local.env
    Application = local.app
    Purpose     = "Docker build and ECR push"
  }
}
