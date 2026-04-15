# ================================================================================
# File: data.tf
# ================================================================================
# Purpose:
#   Resolve resources created by 01-backend (and 02-worker) by name so the API
#   stage does not depend on remote Terraform state. Bucket names (which carry
#   random suffixes) are passed in as variables by apply.sh.
# ================================================================================

variable "media_bucket_name" {
  description = "Private S3 bucket for uploaded originals and generated cartoons."
  type        = string
}

data "aws_sqs_queue" "jobs" {
  name = "${var.name}-jobs"
}

data "aws_dynamodb_table" "jobs" {
  name = "${var.name}-jobs"
}

data "aws_cognito_user_pools" "this" {
  name = "${var.name}-user-pool"
}

data "aws_cognito_user_pool_clients" "this" {
  user_pool_id = tolist(data.aws_cognito_user_pools.this.ids)[0]
}

data "aws_cognito_user_pool" "this" {
  user_pool_id = tolist(data.aws_cognito_user_pools.this.ids)[0]
}

data "aws_ecr_repository" "worker" {
  name = var.name
}

locals {
  media_bucket_arn = "arn:aws:s3:::${var.media_bucket_name}"
  worker_image_uri = "${data.aws_ecr_repository.worker.repository_url}:${var.worker_image_tag}"
  # The SPA app client is the only client in the pool.
  app_client_id = tolist(data.aws_cognito_user_pool_clients.this.client_ids)[0]
}
