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

# ------------------------------------------------------------------------------
# Bedrock model selection — passed in from apply.sh so a single edit there
# retargets the worker Lambda env var, the worker IAM policy, and the
# pre-flight check in check_env.sh.
# ------------------------------------------------------------------------------
variable "bedrock_model_id" {
  description = "Bedrock foundation model ID (e.g. stability.stable-image-control-structure-v1:0)."
  type        = string
}

variable "bedrock_inference_profile_id" {
  description = "Cross-region inference profile ID used at invoke time (e.g. us.stability.stable-image-control-structure-v1:0)."
  type        = string
}

variable "bedrock_model_regions" {
  description = "Regions the inference profile may route to. Each needs an IAM Resource entry for the underlying foundation model."
  type        = list(string)
  default     = ["us-east-1", "us-east-2", "us-west-2"]
}
