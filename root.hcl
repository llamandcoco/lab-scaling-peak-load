locals {
  aws_region = "ca-central-1"
  env        = "lab"
  app        = "scaling-peak-load"
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"
}
EOF
}
