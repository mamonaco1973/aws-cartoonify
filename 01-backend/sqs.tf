# ================================================================================
# File: sqs.tf
# ================================================================================
# Purpose:
#   SQS queue that decouples the /generate API from the Bedrock worker Lambda.
#   Visibility timeout is tuned to exceed the worker Lambda's max runtime so
#   that a single slow Bedrock invocation cannot trigger duplicate processing.
# ================================================================================

resource "aws_sqs_queue" "jobs" {
  name                       = "${var.name}-jobs"
  visibility_timeout_seconds = 180  # > worker Lambda timeout (120s)
  message_retention_seconds  = 86400
  delay_seconds              = 0
  max_message_size           = 262144
  receive_wait_time_seconds  = 10

  tags = {
    Name    = "${var.name}-jobs"
    Purpose = "cartoonify-service"
  }
}

output "jobs_queue_url" {
  value = aws_sqs_queue.jobs.id
}

output "jobs_queue_arn" {
  value = aws_sqs_queue.jobs.arn
}

output "jobs_queue_name" {
  value = aws_sqs_queue.jobs.name
}
