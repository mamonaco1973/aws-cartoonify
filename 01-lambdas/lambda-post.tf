# ================================================================================
# File: lambda_create.tf
# ================================================================================
# Purpose:
#   Deploys the "Create Note" Lambda function that writes new notes
#   to the DynamoDB notes table. This function is intended to be
#   invoked by an API Gateway route such as POST /notes.
#
# Notes:
#   - Uses Python 3.11 runtime.
#   - Writes items to the DynamoDB "notes" table defined in dynamodb.tf.
# ================================================================================

# --------------------------------------------------------------------------------
# RESOURCE: aws_iam_role.lambda_create_role
# --------------------------------------------------------------------------------
# Description:
#   IAM role assumed by the Lambda function during execution.
#   The trust policy allows the Lambda service to assume this
#   role at runtime.
# --------------------------------------------------------------------------------
resource "aws_iam_role" "lambda_create_role" {
  name = "notes-cognito-create-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
      Effect    = "Allow"
    }]
  })
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_iam_role_policy_attachment.lambda_create_basic
# --------------------------------------------------------------------------------
# Description:
#   Attaches the AWS-managed basic execution policy to grant
#   CloudWatch Logs access for the Lambda function.
# --------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "lambda_create_basic" {
  role       = aws_iam_role.lambda_create_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_iam_role_policy.lambda_create_dynamo
# --------------------------------------------------------------------------------
# Description:
#   Inline IAM policy that allows the Lambda function to write
#   items to the DynamoDB notes table.
# --------------------------------------------------------------------------------
resource "aws_iam_role_policy" "lambda_create_dynamo" {
  name = "notes-cognito-create-dynamo"
  role = aws_iam_role.lambda_create_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem"],
      Resource = aws_dynamodb_table.notes.arn
    }]
  })
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_lambda_function.lambda_create
# --------------------------------------------------------------------------------
# Description:
#   Deploys the "create-create" Lambda function. The function
#   creates new notes in DynamoDB and returns the created item.
#
# Handler:
#   notes.create_handler  (code/notes.py)
# --------------------------------------------------------------------------------
resource "aws_lambda_function" "lambda_create" {
  function_name    = "create-note-cognito"
  role             = aws_iam_role.lambda_create_role.arn
  runtime          = "python3.14"
  handler          = "notes.create_handler"
  filename         = data.archive_file.lambdas_zip.output_path
  source_code_hash = data.archive_file.lambdas_zip.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      NOTES_TABLE_NAME = aws_dynamodb_table.notes.name
    }
  }
}
