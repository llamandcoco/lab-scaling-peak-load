terraform {
  source = "../../../../infra-modules/terraform/security-group"
}

include {
  path = find_in_parent_folders("root.hcl")
}

locals {
  parent_locals = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  env           = local.parent_locals.env
  app           = local.parent_locals.app
}

dependency "net" {
  config_path = "../../00-shared-infra/01-networking"

  mock_outputs = {
    vpc_id = "vpc-mock123456"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
}

dependency "alb_sg" {
  config_path = "../../00-shared-infra/02-alb-sg"

  mock_outputs = {
    security_group_id = "sg-mock123456"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
}

inputs = {
  vpc_id     = dependency.net.outputs.vpc_id
  name       = "${local.env}-${local.app}-instance-sg"
  description = "Instance security group for ${local.env}-${local.app}"

  ingress_rules = [{
    protocol                 = "tcp"
    from_port                = 80
    to_port                  = 80
    source_security_group_id = dependency.alb_sg.outputs.security_group_id
  }]

  # Let AWS manage default egress rule (allow all outbound)
  egress_rules = []
  enable_default_egress_rule = true
}
