# ================================================================================
# File: lambda-worker.tf
# ================================================================================
# Purpose:
#   Deploys the container-image Lambda that consumes cartoonify jobs from SQS
#   and invokes Amazon Nova Canvas via Bedrock. The image is produced by the
#   02-worker stage and tagged with var.worker_image_tag.
#
#   Bedrock IAM is scoped to the Nova Canvas foundation model only.
# ================================================================================

# --------------------------------------------------------------------------------
# IAM role
# --------------------------------------------------------------------------------
resource "aws_iam_role" "worker_role" {
  name = "${var.name}-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Principal = { Service = "lambda.amazonaws.com" },
      Effect    = "Allow"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_basic" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "worker_sqs" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

resource "aws_iam_role_policy" "worker_inline" {
  name = "${var.name}-worker-inline"
  role = aws_iam_role.worker_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "JobsTableRW",
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ],
        Resource = data.aws_dynamodb_table.jobs.arn
      },
      {
        Sid    = "MediaObjectRW",
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ],
        Resource = "${local.media_bucket_arn}/*"
      },
      {
        Sid    = "BedrockInvokeNovaCanvas",
        Effect = "Allow",
        Action = ["bedrock:InvokeModel"],
        Resource = "arn:aws:bedrock:${data.aws_region.current.id}::foundation-model/amazon.nova-canvas-v1:0"
      }
    ]
  })
}

# --------------------------------------------------------------------------------
# Worker Lambda (container image from ECR)
# --------------------------------------------------------------------------------
resource "aws_lambda_function" "worker" {
  function_name = "${var.name}-worker"
  role          = aws_iam_role.worker_role.arn
  package_type  = "Image"
  image_uri     = local.worker_image_uri
  timeout       = 120
  memory_size   = 2048

  environment {
    variables = {
      JOBS_TABLE_NAME   = data.aws_dynamodb_table.jobs.name
      MEDIA_BUCKET_NAME = var.media_bucket_name
      BEDROCK_MODEL_ID  = "amazon.nova-canvas-v1:0"
    }
  }

  tracing_config {
    mode = "PassThrough"
  }

  tags = {
    Name = "${var.name}-worker"
  }
}

# --------------------------------------------------------------------------------
# SQS → worker event source mapping
# --------------------------------------------------------------------------------
resource "aws_lambda_event_source_mapping" "worker_sqs" {
  event_source_arn = data.aws_sqs_queue.jobs.arn
  function_name    = aws_lambda_function.worker.arn
  batch_size       = 1
  enabled          = true
}
