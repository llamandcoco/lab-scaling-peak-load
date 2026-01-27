terraform {
  source = "github.com/llamandcoco/infra-modules//terraform/stack/networking?ref=${local.common.networking_ref}"
}

include {
  path = find_in_parent_folders("root.hcl")
}

locals {
  parent_locals = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  env           = local.parent_locals.env
  app           = local.parent_locals.app
  common        = read_terragrunt_config("../_env_common.hcl").locals
}

inputs = {
  name       = local.common.name_prefix
  cidr_block = local.common.vpc_cidr
  azs        = local.common.azs

  public_subnet_cidrs  = local.common.public_subnet_cidrs
  private_subnet_cidrs = local.common.private_subnet_cidrs

  # Disable database subnets for this lab
  database_subnet_cidrs = []

  enable_dns_support       = true
  enable_dns_hostnames     = true
  map_public_ip_on_launch  = false

  # ALB needs IGW, instances need NAT for ECR pulls
  internet_gateway_enabled = true
  nat_gateway_mode         = "per_az"  # One NAT per AZ for HA (each AZ independent)

  # Kubernetes subnet tags for EKS/ALB discovery
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                   = "1"
    "kubernetes.io/cluster/lab-scaling-peak-load-eks"   = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb"                            = "1"
    "kubernetes.io/cluster/lab-scaling-peak-load-eks"   = "shared"
  }

  tags = {
    Environment = local.env
    Application = local.app
  }
}
