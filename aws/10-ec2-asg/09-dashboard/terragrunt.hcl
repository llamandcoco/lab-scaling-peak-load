terraform {
  source = "../../../../infra-modules/terraform/cloudwatch-dashboard"
}

include {
  path = find_in_parent_folders("root.hcl")
}

dependency "asg" {
  config_path = "../06-asg"
}

dependency "alb" {
  config_path = "../../00-shared-infra/03-alb"

  mock_outputs = {
    alb_arn                  = "arn:aws:elasticloadbalancing:ca-central-1:123456789012:loadbalancer/app/mock-alb/1234567890abcdef"
    alb_arn_suffix           = "app/mock-alb/1234567890abcdef"
    target_group_arns        = { "lab-tg" = "arn:aws:elasticloadbalancing:ca-central-1:123456789012:targetgroup/lab-tg/1234567890abcdef" }
    target_group_arn_suffixes = { "lab-tg" = "targetgroup/lab-tg/1234567890abcdef" }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "eb" {
  config_path = "../08-eventbridge"
}

locals { 
  parent_locals      = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  env                = local.parent_locals.env
  app                = local.parent_locals.app
  common             = read_terragrunt_config(find_in_parent_folders("_env_common.hcl")).locals
  alb_metrics_prefix = "AWS/ApplicationELB"
  tg_metrics_prefix  = "AWS/ApplicationELB"
}

# Extract ALB name from ARN for metrics

inputs = {
  dashboard_name = "${local.env}-${local.app}"

  widgets = [
    # Row 1: Key Metrics
    {
      type   = "metric"
      width  = 6
      height = 6
      properties = {
        metrics = [
          ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", dependency.asg.outputs.asg_name, { stat = "Average", label = "In Service" }],
          [".", "GroupDesiredCapacity", "AutoScalingGroupName", dependency.asg.outputs.asg_name, { stat = "Average", label = "Desired" }],
          [".", "GroupPendingInstances", "AutoScalingGroupName", dependency.asg.outputs.asg_name, { stat = "Average", label = "Pending" }]
        ]
        period = 60
        stat   = "Average"
        region = "ca-central-1"
        title  = "ASG Instance Count"
        yAxis = {
          left = { min = 0 }
        }
      }
    },
    {
      type   = "metric"
      width  = 6
      height = 6
      properties = {
        metrics = [
          ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", dependency.asg.outputs.asg_name, { stat = "Average", label = "Avg CPU" }],
          [".", ".", "AutoScalingGroupName", dependency.asg.outputs.asg_name, { stat = "Maximum", label = "Max CPU" }]
        ]
        period = 60
        stat   = "Average"
        region = "ca-central-1"
        title  = "EC2 CPU Utilization"
        yAxis = {
          left = { min = 0, max = 100 }
        }
      }
    },
    {
      type   = "metric"
      width  = 6
      height = 6
      properties = {
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", dependency.alb.outputs.alb_arn_suffix, { stat = "Sum", label = "Total RPS" }],
          [".", "TargetResponseTime", "LoadBalancer", dependency.alb.outputs.alb_arn_suffix, { stat = "Average", label = "Response Time (s)" }]
        ]
        period = 60
        stat   = "Average"
        region = "ca-central-1"
        title  = "ALB Requests & Response Time"
      }
    },
    {
      type   = "metric"
      width  = 6
      height = 6
      properties = {
        metrics = [
          ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "TargetGroup", dependency.alb.outputs.target_group_arn_suffixes["lab-tg"], "LoadBalancer", dependency.alb.outputs.alb_arn_suffix, { stat = "Sum", label = "2xx" }],
          [".", "HTTPCode_Target_4XX_Count", "TargetGroup", dependency.alb.outputs.target_group_arn_suffixes["lab-tg"], "LoadBalancer", dependency.alb.outputs.alb_arn_suffix, { stat = "Sum", label = "4xx" }],
          [".", "HTTPCode_Target_5XX_Count", "TargetGroup", dependency.alb.outputs.target_group_arn_suffixes["lab-tg"], "LoadBalancer", dependency.alb.outputs.alb_arn_suffix, { stat = "Sum", label = "5xx" }]
        ]
        period = 60
        stat   = "Sum"
        region = "ca-central-1"
        title  = "HTTP Response Codes"
        yAxis = {
          left = { min = 0 }
        }
      }
    },
    # Row 2: Target Health
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        metrics = [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", dependency.alb.outputs.target_group_arn_suffixes["lab-tg"], "LoadBalancer", dependency.alb.outputs.alb_arn_suffix, { stat = "Average", label = "Healthy Targets" }],
          [".", "UnHealthyHostCount", "TargetGroup", dependency.alb.outputs.target_group_arn_suffixes["lab-tg"], "LoadBalancer", dependency.alb.outputs.alb_arn_suffix, { stat = "Average", label = "Unhealthy Targets" }]
        ]
        period = 60
        stat   = "Average"
        region = "ca-central-1"
        title  = "ALB Target Health"
        yAxis = {
          left = { min = 0 }
        }
      }
    },
    # Row 3: Event Log
    {
      type   = "log"
      width  = 12
      height = 6
      properties = {
        query = "SOURCE '${dependency.eb.outputs.log_group_name}' | fields @timestamp, detail.alarmName, detail.state.value, detail.EC2InstanceId, detail.targetHealth.state | sort @timestamp desc"
        region = "ca-central-1"
        title  = "ASG & Alarm Events (Last 1h)"
      }
    }
  ]
}
