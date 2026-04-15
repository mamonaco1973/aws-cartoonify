# ================================================================================
# File: ecr.tf
# ================================================================================
# Purpose:
#   ECR repository for the worker Lambda container image. Created in 01-backend
#   so that the 02-worker stage (docker build/push) can target it before
#   03-api creates the Lambda that consumes the image.
# ================================================================================

resource "aws_ecr_repository" "worker" {
  name                 = var.name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.name}-worker-ecr"
  }
}

output "worker_repo_name" {
  value = aws_ecr_repository.worker.name
}

output "worker_repo_url" {
  value = aws_ecr_repository.worker.repository_url
}
