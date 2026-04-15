# ================================================================================
# File: lambda-api.tf
# ================================================================================
# Purpose:
#   Zip-packages the API Lambda source from ./code and deploys the five
#   Cognito-authorized API Lambdas:
#     - upload_url  POST   /upload-url
#     - submit      POST   /generate
#     - result      GET    /result/{job_id}
#     - history     GET    /history
#     - delete      DELETE /history/{job_id}
#
#   All five share one zip and one IAM role — each has the same narrow needs
#   (DynamoDB PK=owner, media bucket, SQS send) and splitting roles would add
#   noise without meaningfully narrowing blast radius.
# ================================================================================

# --------------------------------------------------------------------------------
# Package ./code as a single zip shared by all API Lambdas.
# --------------------------------------------------------------------------------
data "archive_file" "api_zip" {
  type        = "zip"
  source_dir  = "${path.module}/code"
  output_path = "${path.module}/api.zip"
}

# --------------------------------------------------------------------------------
# IAM role for the API Lambdas
# --------------------------------------------------------------------------------
resource "aws_iam_role" "api_lambda_role" {
  name = "${var.name}-api-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Principal = { Service = "lambda.amazonaws.com" },
      Effect    = "Allow"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_basic" {
  role       = aws_iam_role.api_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "api_inline" {
  name = "${var.name}-api-inline"
  role = aws_iam_role.api_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "JobsTableRW",
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query"
        ],
        Resource = data.aws_dynamodb_table.jobs.arn
      },
      {
        Sid    = "MediaBucketObjectRW",
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload"
        ],
        Resource = "${local.media_bucket_arn}/*"
      },
      {
        Sid    = "MediaBucketList",
        Effect = "Allow",
        Action = ["s3:ListBucket"],
        Resource = local.media_bucket_arn
      },
      {
        Sid    = "SubmitToQueue",
        Effect = "Allow",
        Action = ["sqs:SendMessage"],
        Resource = data.aws_sqs_queue.jobs.arn
      }
    ]
  })
}

# --------------------------------------------------------------------------------
# Shared environment block
# --------------------------------------------------------------------------------
locals {
  api_env = {
    JOBS_TABLE_NAME   = data.aws_dynamodb_table.jobs.name
    MEDIA_BUCKET_NAME = var.media_bucket_name
    JOBS_QUEUE_URL    = data.aws_sqs_queue.jobs.url
  }
}

# --------------------------------------------------------------------------------
# Lambda functions
# --------------------------------------------------------------------------------
resource "aws_lambda_function" "upload_url" {
  function_name    = "${var.name}-upload-url"
  role             = aws_iam_role.api_lambda_role.arn
  runtime          = "python3.11"
  handler          = "upload_url.lambda_handler"
  filename         = data.archive_file.api_zip.output_path
  source_code_hash = data.archive_file.api_zip.output_base64sha256
  timeout          = 10
  environment { variables = local.api_env }
}

resource "aws_lambda_function" "submit" {
  function_name    = "${var.name}-submit"
  role             = aws_iam_role.api_lambda_role.arn
  runtime          = "python3.11"
  handler          = "submit.lambda_handler"
  filename         = data.archive_file.api_zip.output_path
  source_code_hash = data.archive_file.api_zip.output_base64sha256
  timeout          = 10
  environment { variables = local.api_env }
}

resource "aws_lambda_function" "result" {
  function_name    = "${var.name}-result"
  role             = aws_iam_role.api_lambda_role.arn
  runtime          = "python3.11"
  handler          = "result.lambda_handler"
  filename         = data.archive_file.api_zip.output_path
  source_code_hash = data.archive_file.api_zip.output_base64sha256
  timeout          = 10
  environment { variables = local.api_env }
}

resource "aws_lambda_function" "history" {
  function_name    = "${var.name}-history"
  role             = aws_iam_role.api_lambda_role.arn
  runtime          = "python3.11"
  handler          = "history.lambda_handler"
  filename         = data.archive_file.api_zip.output_path
  source_code_hash = data.archive_file.api_zip.output_base64sha256
  timeout          = 10
  environment { variables = local.api_env }
}

resource "aws_lambda_function" "delete" {
  function_name    = "${var.name}-delete"
  role             = aws_iam_role.api_lambda_role.arn
  runtime          = "python3.11"
  handler          = "delete.lambda_handler"
  filename         = data.archive_file.api_zip.output_path
  source_code_hash = data.archive_file.api_zip.output_base64sha256
  timeout          = 10
  environment { variables = local.api_env }
}
