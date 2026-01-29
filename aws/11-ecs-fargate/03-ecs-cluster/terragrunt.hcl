terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/ecs-cluster?ref=${local.common.ecs_cluster_ref}"
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
  name = "${local.env}-${local.app}-ecs"

  enable_container_insights = true

  tags = {
    Environment = local.env
    Application = local.app
  }
}
