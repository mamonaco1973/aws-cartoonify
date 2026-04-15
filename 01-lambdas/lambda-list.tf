# ================================================================================
# File: lambda_list.tf
# ================================================================================
# Purpose:
#   Deploys the "List Notes" Lambda function that retrieves all notes
#   from the DynamoDB notes table. This function is intended to be
#   invoked by an API Gateway route such as GET /notes.
#
# Notes:
#   - Uses Python 3.11 runtime.
#   - Reads items from the DynamoDB "notes" table defined in dynamodb.tf.
# ================================================================================

# --------------------------------------------------------------------------------
# RESOURCE: aws_iam_role.lambda_list_role
# --------------------------------------------------------------------------------
# Description:
#   IAM role assumed by the Lambda function during execution.
#   The trust policy allows the Lambda service to assume this
#   role at runtime.
# --------------------------------------------------------------------------------
resource "aws_iam_role" "lambda_list_role" {
  name = "notes-cognito-list-role"

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
# RESOURCE: aws_iam_role_policy_attachment.lambda_list_basic
# --------------------------------------------------------------------------------
# Description:
#   Attaches the AWS-managed basic execution policy to grant
#   CloudWatch Logs access for the Lambda function.
# --------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "lambda_list_basic" {
  role       = aws_iam_role.lambda_list_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_iam_role_policy.lambda_list_dynamo
# --------------------------------------------------------------------------------
# Description:
#   Inline IAM policy that allows the Lambda function to query
#   items from the DynamoDB notes table.
# --------------------------------------------------------------------------------
resource "aws_iam_role_policy" "lambda_list_dynamo" {
  name = "notes-cognito-list-dynamo"
  role = aws_iam_role.lambda_list_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:Query"],
      Resource = aws_dynamodb_table.notes.arn
    }]
  })
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_lambda_function.lambda_list
# --------------------------------------------------------------------------------
# Description:
#   Deploys the "list-note" Lambda function. The function
#   queries DynamoDB by partition key and returns all notes.
#
# Handler:
#   notes.list_handler  (code/notes.py)
# --------------------------------------------------------------------------------
resource "aws_lambda_function" "lambda_list" {
  function_name    = "list-notes-cognito"
  role             = aws_iam_role.lambda_list_role.arn
  runtime          = "python3.14"
  handler          = "notes.list_handler"
  filename         = data.archive_file.lambdas_zip.output_path
  source_code_hash = data.archive_file.lambdas_zip.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      NOTES_TABLE_NAME = aws_dynamodb_table.notes.name
    }
  }
}
