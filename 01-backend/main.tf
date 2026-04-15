# ================================================================================
# File: main.tf
# ================================================================================
# Purpose:
#   AWS provider + shared data sources for the cartoonify backend stack.
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

resource "random_id" "suffix" {
  byte_length = 3
}
