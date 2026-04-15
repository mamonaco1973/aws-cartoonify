# ================================================================================
# File: lambda_get.tf
# ================================================================================
# Purpose:
#   Deploys the "Get Note" Lambda function that retrieves a single note
#   from DynamoDB. This function is intended to be invoked by an API
#   Gateway route such as GET /notes/{id}.
#
# Notes:
#   - Uses Python 3.11 runtime.
#   - Reads from the DynamoDB "notes" table defined in dynamodb.tf.
#   - Demo mode uses owner="global" in code; the table access is still
#     GetItem against the table ARN.
# ================================================================================

# --------------------------------------------------------------------------------
# RESOURCE: aws_iam_role.lambda_get_role
# --------------------------------------------------------------------------------
# Description:
#   IAM role assumed by the Lambda function at runtime. The trust
#   policy allows the Lambda service to assume this role.
# --------------------------------------------------------------------------------
resource "aws_iam_role" "lambda_get_role" {
  name = "notes-cognito-get-role"

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
# RESOURCE: aws_iam_role_policy_attachment.lambda_get_basic
# --------------------------------------------------------------------------------
# Description:
#   Attaches the AWS-managed basic execution policy to allow the
#   Lambda function to write logs to Amazon CloudWatch.
# --------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "lambda_get_basic" {
  role       = aws_iam_role.lambda_get_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_iam_role_policy.lambda_get_dynamo
# --------------------------------------------------------------------------------
# Description:
#   Inline IAM policy granting DynamoDB read access to the Notes table.
#   Required for retrieving notes using (owner, id).
# --------------------------------------------------------------------------------
resource "aws_iam_role_policy" "lambda_get_dynamo" {
  name = "notes-cognito-get-dynamo"
  role = aws_iam_role.lambda_get_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["dynamodb:GetItem"],
      Resource = aws_dynamodb_table.notes.arn
    }]
  })
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_lambda_function.lambda_get
# --------------------------------------------------------------------------------
# Description:
#   Deploys the "get-note" Lambda function. The function reads a single
#   note from DynamoDB using owner + id and returns it to API Gateway.
# --------------------------------------------------------------------------------
resource "aws_lambda_function" "lambda_get" {
  function_name    = "get-note-cognito"
  role             = aws_iam_role.lambda_get_role.arn
  runtime          = "python3.14"
  handler          = "notes.get_handler"
  filename         = data.archive_file.lambdas_zip.output_path
  source_code_hash = data.archive_file.lambdas_zip.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      NOTES_TABLE_NAME = aws_dynamodb_table.notes.name
    }
  }
}

# --------------------------------------------------------------------------------
# DATA: archive_file.lambdas_zip
# --------------------------------------------------------------------------------
# Description:
#   Packages Lambda source code from the local "code" directory
#   into a ZIP archive for deployment.
#
# Expected code layout:
#   code/
#     get.py
#     list.py
#     create.py
#     update.py
#     delete.py
# --------------------------------------------------------------------------------
data "archive_file" "lambdas_zip" {
  type        = "zip"
  source_dir  = "${path.module}/code"
  output_path = "${path.module}/lambdas.zip"
}
