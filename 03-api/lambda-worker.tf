# ================================================================================
# File: lambda-worker.tf
# ================================================================================
# Purpose:
#   Deploys the container-image Lambda that consumes cartoonify jobs from SQS
#   and invokes a Bedrock foundation model. The image is produced by the
#   02-worker stage and tagged with var.worker_image_tag.
#
#   The Bedrock model is fully parameterized via var.bedrock_model_id /
#   var.bedrock_inference_profile_id / var.bedrock_model_regions so it can be
#   retargeted from apply.sh without editing Terraform. IAM is scoped to that
#   single model and its inference profile.
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
        Sid    = "BedrockInvokeModel",
        Effect = "Allow",
        Action = ["bedrock:InvokeModel"],
        Resource = concat(
          # Cross-region inference profile (actual invocation target)
          [
            "arn:aws:bedrock:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.bedrock_inference_profile_id}"
          ],
          # Underlying foundation model in every region the profile may route to
          [
            for region in var.bedrock_model_regions :
            "arn:aws:bedrock:${region}::foundation-model/${var.bedrock_model_id}"
          ]
        )
      },
      {
        # Third-party Bedrock models (e.g. Stability) are gated by an AWS
        # Marketplace subscription. On InvokeModel, Bedrock checks (and, if
        # missing, attempts to create) the subscription on behalf of the
        # invoking principal. Without these permissions the call fails with
        # AccessDeniedException citing aws-marketplace:ViewSubscriptions /
        # aws-marketplace:Subscribe. Amazon's own models (Nova, Titan) do not
        # need this.
        #
        # Resource cannot be scoped — Marketplace actions only support "*".
        Sid    = "BedrockMarketplaceSubscriptionCheck",
        Effect = "Allow",
        Action = [
          "aws-marketplace:ViewSubscriptions",
          "aws-marketplace:Subscribe",
          "aws-marketplace:Unsubscribe"
        ],
        Resource = "*"
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
      BEDROCK_MODEL_ID  = var.bedrock_inference_profile_id
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
