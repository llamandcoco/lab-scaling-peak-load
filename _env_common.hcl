locals {
  # Common environment variables
  name_prefix          = "lab-scaling-peak-load"
  vpc_cidr             = "10.50.0.0/16"
  azs                  = ["ca-central-1a", "ca-central-1b"]
  public_subnet_cidrs  = ["10.50.1.0/24", "10.50.2.0/24"]
  private_subnet_cidrs = ["10.50.10.0/24", "10.50.11.0/24"]
}
