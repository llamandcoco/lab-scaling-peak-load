terraform {
  source = "../../../../infra-modules/terraform/cloudwatch-alarm"
}

include {
  path = find_in_parent_folders("root.hcl")
}

dependency "asg" {
  config_path = "../03-asg"

  mock_outputs = {
    asg_name = "mock-asg-name"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
}

locals {
  parent_locals = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  env           = local.parent_locals.env
  app           = local.parent_locals.app
}

inputs = {
  alarm_name          = "${local.env}-${local.app}-cpu-alarm"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { AutoScalingGroupName = dependency.asg.outputs.asg_name }
  comparison_operator = "GreaterThanThreshold"
  threshold           = 75
  period              = 60
  evaluation_periods  = 2
  statistic           = "Average"
  treat_missing_data  = "ignore"

  # No alarm actions needed - using target tracking policies instead
  # This alarm is for monitoring/visibility only (75% threshold)
  # Target tracking policies handle automatic scaling at 60% CPU
  alarm_actions = []
}
