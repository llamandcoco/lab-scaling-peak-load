terraform {
  source = "/Users/lama/workspace/llamandcoco/infra-modules//terraform/stack/networking"
}

include {
  path = find_in_parent_folders("root.hcl")
}

locals { 
  parent_locals = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  env           = local.parent_locals.env
  app           = local.parent_locals.app
  common        = read_terragrunt_config(find_in_parent_folders("_env_common.hcl")).locals
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

  tags = {
    Environment = local.env
    Application = local.app
  }
}
