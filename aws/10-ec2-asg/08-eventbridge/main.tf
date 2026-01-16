# EventBridge rules to capture ASG scaling events, CloudWatch alarms, and ALB target health changes

variable "asg_name" {
  description = "Auto Scaling Group name to monitor"
  type        = string
}

# Create CloudWatch Log Group for events
resource "aws_cloudwatch_log_group" "asg_events" {
  name              = "/aws/events/lab-scaling"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_resource_policy" "asg_events" {
  policy_name = "lab-eventbridge-logs-policy"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.asg_events.arn}:*"
    }]
  })
}

# Capture ASG Launch Events
locals {
  rules = {
    "asg-launch-events" = {
      event_pattern = jsonencode({
        source      = ["aws.autoscaling"]
        detail-type = ["EC2 Instance Launch Successful", "EC2 Instance Launch Unsuccessful"]
        detail = {
          AutoScalingGroupName = [var.asg_name]
        }
      })
    }
    "alarm-state-change" = {
      event_pattern = jsonencode({
        source      = ["aws.cloudwatch"]
        detail-type = ["CloudWatch Alarm State Change"]
      })
    }
    "target-health-change" = {
      event_pattern = jsonencode({
        source      = ["aws.elasticloadbalancing"]
        detail-type = ["Elastic Load Balancing Target Health State Change"]
      })
    }
  }
}

resource "aws_cloudwatch_event_rule" "events" {
  for_each      = local.rules
  name          = "lab-${each.key}"
  event_pattern = each.value.event_pattern
  state         = "ENABLED"
}

resource "aws_cloudwatch_event_target" "logs" {
  for_each  = aws_cloudwatch_event_rule.events
  rule      = each.value.name
  target_id = "send-to-logs"
  arn       = "${aws_cloudwatch_log_group.asg_events.arn}:*"
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.asg_events.name
}
