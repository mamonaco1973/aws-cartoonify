# ================================================================================
# File: dynamodb.tf
# ================================================================================
# Purpose:
#   Single table for cartoonify jobs.
#
# Keys:
#   owner  (PK, S) — Cognito JWT sub claim
#   job_id (SK, S) — "<epoch_ms_13digits>-<hex8>" → lexicographically sortable
#                    by submission time; enables efficient daily-quota range
#                    queries via KeyConditionExpression without a GSI.
#
# TTL:
#   ttl (N) — epoch seconds; items auto-expire after 7 days to match the S3
#   lifecycle rule on originals/ and cartoons/.
# ================================================================================

resource "aws_dynamodb_table" "jobs" {
  name         = "${var.name}-jobs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "owner"
  range_key    = "job_id"

  attribute {
    name = "owner"
    type = "S"
  }

  attribute {
    name = "job_id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name = "${var.name}-jobs"
  }
}

output "jobs_table_name" {
  value = aws_dynamodb_table.jobs.name
}

output "jobs_table_arn" {
  value = aws_dynamodb_table.jobs.arn
}
