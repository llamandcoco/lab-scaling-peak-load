terraform {
  source = "../../../../infra-modules/terraform/alb"
}

include {
  path = find_in_parent_folders("root.hcl")
}

dependency "net" {
  config_path = "../01-networking"
}

dependency "alb_sg" {
  config_path = "../02-alb-sg"
}

locals {
  parent_locals = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
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
    target_type      = "ip"  # Changed from "instance" to "ip" for ECS Fargate compatibility
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
