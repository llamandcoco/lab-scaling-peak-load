terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/alb-target-group?ref=${local.common.alb_target_group_ref}"
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

dependency "alb" {
  config_path = "../../00-shared-infra/03-alb"

  mock_outputs = {
    http_listener_arn = "arn:aws:elasticloadbalancing:ca-central-1:123456789012:listener/app/mock-alb/1234567890abcdef/1234567890abcdef"
    listener_arns     = { "80" = "arn:aws:elasticloadbalancing:ca-central-1:123456789012:listener/app/mock-alb/1234567890abcdef/1234567890abcdef" }
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
  name        = "${local.env}-${local.app}-ecs-tg"
  vpc_id      = dependency.net.outputs.vpc_id
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"

  health_check = {
    path                = "/healthz"
    matcher             = "200-399"
    interval            = 20
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  listener_arn      = try(dependency.alb.outputs.http_listener_arn, dependency.alb.outputs.listener_arns["80"])
  listener_priority = 10
  listener_conditions = [
    {
      host_header = {
        values = ["ecs.local"]
      }
    }
  ]

  tags = {
    Environment = local.env
    Application = local.app
  }
}
