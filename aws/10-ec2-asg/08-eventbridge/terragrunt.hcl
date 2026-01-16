terraform {
  source = "."
}

include {
  path = find_in_parent_folders("root.hcl")
}

dependency "asg" {
  config_path = "../06-asg"
}

inputs = {
  asg_name = dependency.asg.outputs.asg_name
}
