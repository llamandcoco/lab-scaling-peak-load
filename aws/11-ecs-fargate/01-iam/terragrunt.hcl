terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/ecs-execution-role?ref=${local.common.ecs_execution_role_ref}"
}

include {
  path = find_in_parent_folders("root.hcl")
}

locals {
  parent_locals = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  common        = read_terragrunt_config("../_env_common.hcl").locals
  env           = local.parent_locals.env
  app           = local.parent_locals.app
}

inputs = {
  name            = "${local.env}-${local.app}-ecs-execution-role"
  enable_ecr      = true
  enable_ssm      = false
  enable_cw_logs  = true
  enable_cw_agent = false

  tags = {
    Environment = local.env
    Application = local.app
  }
}
