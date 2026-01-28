terraform {
  source = "."
}

include {
  path = find_in_parent_folders("root.hcl")
}

dependency "asg" {
  config_path = "../03-asg"

  mock_outputs = {
    asg_name = "mock-asg-name"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  asg_name = dependency.asg.outputs.asg_name
}
