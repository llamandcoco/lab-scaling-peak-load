terraform {
  source = "../../../../infra-modules/terraform/instance-profile"
}

include {
  path = find_in_parent_folders("root.hcl")
}

locals {
  parent_locals = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  env           = local.parent_locals.env
  app           = local.parent_locals.app
}

inputs = {
  name            = "${local.env}-${local.app}-instance-profile"
  enable_ecr      = true
  enable_ssm      = true
  enable_cw_logs  = true
  enable_cw_agent = true
  tags = {
    Environment = local.env
    Application = local.app
  }
}
