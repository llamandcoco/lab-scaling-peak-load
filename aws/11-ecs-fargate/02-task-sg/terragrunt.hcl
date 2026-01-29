terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/security-group?ref=${local.common.security_group_ref}"
}

include {
  path = find_in_parent_folders("root.hcl")
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

locals {
  parent_locals = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  common        = read_terragrunt_config("../_env_common.hcl").locals
  env           = local.parent_locals.env
  app           = local.parent_locals.app
}

inputs = {
  name        = "${local.env}-${local.app}-ecs-task-sg"
  description = "Security group for ECS Fargate tasks"
  vpc_id      = dependency.net.outputs.vpc_id

  ingress_rules = [{
    description              = "Allow traffic from ALB on port 8080"
    from_port                = 8080
    to_port                  = 8080
    protocol                 = "tcp"
    source_security_group_id = dependency.alb_sg.outputs.security_group_id
    cidr_blocks              = []
    ipv6_cidr_blocks         = []
    prefix_list_ids          = []
  }]

  egress_rules = [{
    description              = "Allow all outbound traffic"
    from_port                = 0
    to_port                  = 0
    protocol                 = "-1"
    cidr_blocks              = ["0.0.0.0/0"]
    ipv6_cidr_blocks         = ["::/0"]
    source_security_group_id = null
    prefix_list_ids          = []
  }]

  enable_default_egress_rule = false  # Using custom egress rule above

  tags = {
    Environment = local.env
    Application = local.app
  }
}
