# ================================================================================
# File: main.tf
# ================================================================================
# Purpose:
#   AWS provider + shared variables for the cartoonify API stage. Looks up
#   resources created in 01-backend by name (bucket names, queue name, table
#   name, Cognito pool) so this stack can be applied independently.
# ================================================================================

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

variable "name" {
  type    = string
  default = "cartoonify"
}

variable "worker_image_tag" {
  type    = string
  default = "worker-rc1"
}
