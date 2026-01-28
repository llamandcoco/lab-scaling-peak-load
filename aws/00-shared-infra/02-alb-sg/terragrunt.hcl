terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/security-group?ref=${local.common.security_group_ref}"
}

include {
  path = find_in_parent_folders("root.hcl")
}

dependency "net" {
  config_path = "../01-networking"

  mock_outputs = {
    vpc_id = "vpc-mock123456"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

locals {
  parent_locals = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  common        = read_terragrunt_config("../_env_common.hcl").locals
  env           = local.parent_locals.env
  app           = local.parent_locals.app
}

inputs = {
  vpc_id = dependency.net.outputs.vpc_id

  # Create ALB SG allowing 80 from everywhere
  name        = "${local.env}-${local.app}-alb-sg"
  description = "ALB security group for ${local.env}-${local.app}"
  ingress_rules = [{
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }]
  
  # Let AWS manage default egress rule (allow all outbound)
  egress_rules = []
  enable_default_egress_rule = true
}
