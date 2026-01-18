locals {
  # Pin Terraform module sources to a specific commit SHA
  module_ref          = "522b9993b690d885f8371f3353da2957ddd8ebb1"
  parameter_store_ref = local.module_ref
  ecr_ref             = local.module_ref
  codebuild_ref       = local.module_ref
  codepipeline_ref    = local.module_ref
}
