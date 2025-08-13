locals {
  # Define the local variable for the project name
  project_name = "dify-test"

  # Define the local variable for the region
  region = "ap-northeast-1"

  # Define the local variable for the environment
  environment = "dev"

  # Define a local variable for the resource base name
  base_name = "${local.project_name}-${local.environment}-${local.region}"
}
