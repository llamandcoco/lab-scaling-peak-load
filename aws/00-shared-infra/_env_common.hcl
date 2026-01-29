locals {
  vpc_cidr             = "10.50.0.0/16"
  azs                  = ["ca-central-1a", "ca-central-1b"]
  public_subnet_cidrs  = ["10.50.10.0/24", "10.50.11.0/24"]
  private_subnet_cidrs = ["10.50.20.0/24", "10.50.21.0/24"]
  name_prefix          = "lab-auto-scaling"

  # Module version references
  networking_ref     = "main"
  security_group_ref = "main"
  alb_ref            = "main"
}
