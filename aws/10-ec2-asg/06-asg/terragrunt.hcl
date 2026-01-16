terraform {
  source = "../../../../infra-modules/terraform/autoscaling"
}

include {
  path = find_in_parent_folders("root.hcl")
}

dependency "alb" {
  config_path = "../05-alb"
}

dependency "net" {
  config_path = "../02-networking"
}

dependency "inst_sg" {
  config_path = "../04-instance-sg"
}

dependency "iam" {
  config_path = "../01-iam"
}

locals {
  parent_locals = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  env           = local.parent_locals.env
  app           = local.parent_locals.app
}

inputs = {
  name             = "${local.env}-${local.app}-asg"

  # Private subnets from networking stack
  vpc_subnet_ids   = dependency.net.outputs.private_subnet_ids

  # Attach ALB TG from dependency
  target_group_arns = try([dependency.alb.outputs.target_group_arns["lab-tg"]], [])
  alb_target_group_resource_label = "${dependency.alb.outputs.alb_arn_suffix}/${dependency.alb.outputs.target_group_arn_suffixes["lab-tg"]}"

  min_size         = 1
  max_size         = 6
  desired_capacity = 1

  instance_type = "t3.micro"

  # Amazon Linux 2023 via SSM (module defaults to lookup)
  use_ssm_ami_lookup = true

  security_group_ids = try([dependency.inst_sg.outputs.security_group_id], [])

  # IAM instance profile should allow ECR pull, SSM get-parameter, CloudWatch logs
  iam_instance_profile_name = dependency.iam.outputs.instance_profile_name

  # User data to pull and run container from ECR + install CloudWatch Agent
  user_data = <<-EOT
    #!/bin/bash
    set -xe
    dnf update -y
    dnf install -y docker aws-cli amazon-cloudwatch-agent

    systemctl enable --now docker
    usermod -aG docker ec2-user || true

    # Configure CloudWatch Agent to collect memory metrics
    cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<'EOF'
    {
      "agent": {
        "region": "ca-central-1",
        "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
        "debug": false
      },
      "metrics": {
        "namespace": "CWAgent",
        "metrics_collected": {
          "mem": {
            "measurement": [
              {
                "name": "mem_used_percent",
                "rename": "MemoryUtilization",
                "unit": "Percent"
              }
            ],
            "metrics_collection_interval": 60
          },
          "cpu": {
            "measurement": [
              {
                "name": "cpu_usage_active",
                "rename": "CPUUtilization",
                "unit": "Percent"
              }
            ],
            "metrics_collection_interval": 60
          }
        }
      }
    }
    EOF

    # Start CloudWatch Agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config \
      -m ec2 \
      -s \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

    # Pull and run container from ECR
    TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    REGION=$(curl -sH "X-aws-ec2-metadata-token: $${TOKEN}" http://169.254.169.254/latest/meta-data/placement/region)
    REGION=$${REGION:-ca-central-1}
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    REPO_URI="$${ACCOUNT_ID}.dkr.ecr.$${REGION}.amazonaws.com/lab-scaling-peak-load-registry"
    IMAGE_TAG="latest"

    aws ecr get-login-password --region "$${REGION}" | docker login --username AWS --password-stdin "$${REPO_URI}"
    docker pull "$${REPO_URI}:$${IMAGE_TAG}"
    docker run -d --name app --restart always -p 80:8080 "$${REPO_URI}:$${IMAGE_TAG}"
  EOT

  enable_target_tracking_cpu = true
  cpu_target_value           = 60

  # RPS-based scaling (ALBRequestCountPerTarget)
  enable_target_tracking_alb = true
  alb_target_value           = 100  # target 100 RPS per instance
  alb_target_group_arn       = try(dependency.alb.outputs.target_group_arns["lab-tg"], null)

  # Memory-based alarm for manual step scaling (optional)
  enable_memory_alarm     = true
  memory_alarm_threshold  = 80  # % memory utilization
  memory_alarm_namespace  = "CWAgent"
  memory_alarm_metric_name = "mem_used_percent"
}
