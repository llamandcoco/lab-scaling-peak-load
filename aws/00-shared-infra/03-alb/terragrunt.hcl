terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/alb?ref=${local.common.alb_ref}"
}

include {
  path = find_in_parent_folders("root.hcl")
}

dependency "net" {
  config_path = "../01-networking"

  mock_outputs = {
    vpc_id             = "vpc-mock123456"
    public_subnet_ids  = ["subnet-mock1", "subnet-mock2"]
    private_subnet_ids = ["subnet-mock3", "subnet-mock4"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "alb_sg" {
  config_path = "../02-alb-sg"

  mock_outputs = {
    security_group_id = "sg-mock123456"
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
  alb_name           = "${local.env}-${local.app}-alb"
  vpc_id             = dependency.net.outputs.vpc_id
  load_balancer_type = "application"
  internal           = false
  security_group_ids = [dependency.alb_sg.outputs.security_group_id]
  subnets            = dependency.net.outputs.public_subnet_ids

  listeners = [{
    port     = 80
    protocol = "HTTP"
    
    default_action = {
      type              = "forward"
      target_group_name = "lab-tg"
      redirect          = null
      fixed_response    = null
    }
  }]

  target_groups = [{
    name             = "lab-tg"
    port             = 80
    protocol         = "HTTP"
    target_type      = "instance"  # Required for EC2 ASG compatibility
    health_check = {
      path                = "/healthz"
      matcher             = "200-399"
      interval            = 20
      timeout             = 5
      healthy_threshold   = 2
      unhealthy_threshold = 2
    }
  }]
}
