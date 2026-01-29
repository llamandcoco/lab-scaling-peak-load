terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/ecs-service?ref=${local.common.ecs_service_ref}"
}

include {
  path = find_in_parent_folders("root.hcl")
}

dependency "cluster" {
  config_path = "../03-ecs-cluster"
}

dependency "net" {
  config_path = "../../00-shared-infra/01-networking"

  mock_outputs = {
    vpc_id              = "vpc-mock123456"
    private_subnet_ids  = ["subnet-mock1", "subnet-mock2"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
}

dependency "alb" {
  config_path = "../../00-shared-infra/03-alb"

  mock_outputs = {
    alb_arn                  = "arn:aws:elasticloadbalancing:ca-central-1:123456789012:loadbalancer/app/mock-alb/1234567890abcdef"
    alb_arn_suffix           = "app/mock-alb/1234567890abcdef"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
}

dependency "tg" {
  config_path = "../05-alb-tg"

  mock_outputs = {
    target_group_arn        = "arn:aws:elasticloadbalancing:ca-central-1:123456789012:targetgroup/mock-ecs-tg/1234567890abcdef"
    target_group_arn_suffix = "targetgroup/mock-ecs-tg/1234567890abcdef"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
}

dependency "iam" {
  config_path = "../01-iam"
}

dependency "task_sg" {
  config_path = "../02-task-sg"
}

locals {
  parent_locals = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  common        = read_terragrunt_config("../_env_common.hcl").locals
  env           = local.parent_locals.env
  app           = local.parent_locals.app
  region        = local.parent_locals.aws_region
}

inputs = {
  cluster_id   = dependency.cluster.outputs.cluster_id
  service_name = "${local.env}-${local.app}-service"

  # Container configuration
  container_name  = "app"
  container_image = "${get_aws_account_id()}.dkr.ecr.${local.region}.amazonaws.com/lab-scaling-peak-load-registry:latest"
  container_port  = 8080

  # Fargate sizing (0.25 vCPU, 0.5 GB - similar to t3.micro)
  cpu    = "256"
  memory = "512"

  # Networking
  subnet_ids         = dependency.net.outputs.private_subnet_ids
  security_group_ids = [dependency.task_sg.outputs.security_group_id]
  assign_public_ip   = false  # Using NAT gateway for internet access

  # ALB integration
  target_group_arn       = dependency.tg.outputs.target_group_arn
  health_check_grace_period = 60

  # IAM
  execution_role_arn = dependency.iam.outputs.role_arn
  task_role_arn      = null  # No additional task permissions needed

  # Service configuration
  desired_count                   = 1
  deployment_maximum_percent      = 200
  deployment_minimum_healthy_percent = 100
  enable_ecs_exec                 = false  # Set to true for debugging if needed

  # Auto Scaling - matching EC2 ASG configuration
  min_capacity           = 1
  max_capacity           = 6
  enable_cpu_scaling     = true
  target_cpu_utilization = 60
  enable_memory_scaling  = false

  # RPS-based scaling (ALBRequestCountPerTarget)
  enable_alb_scaling              = true
  target_request_count_per_target = 100  # Scale when >100 requests per task
  alb_resource_label              = "${dependency.alb.outputs.alb_arn_suffix}/${dependency.tg.outputs.target_group_arn_suffix}"

  scale_in_cooldown      = 300
  scale_out_cooldown     = 60

  # CloudWatch Logs
  log_retention_days = 7

  # Environment variables (if needed)
  environment_variables = []

  tags = {
    Environment = local.env
    Application = local.app
  }
}
