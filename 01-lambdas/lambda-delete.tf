# ================================================================================
# File: lambda_delete.tf
# ================================================================================
# Purpose:
#   Deploys the "Delete Note" Lambda function that deletes an existing
#   note from the DynamoDB notes table. This function is intended to be
#   invoked by an API Gateway route such as DELETE /notes/{id}.
#
# Notes:
#   - Uses Python 3.11 runtime.
#   - Deletes items from the DynamoDB "notes" table defined in dynamodb.tf.
# ================================================================================

# --------------------------------------------------------------------------------
# RESOURCE: aws_iam_role.lambda_delete_role
# --------------------------------------------------------------------------------
# Description:
#   IAM role assumed by the Lambda function during execution.
#   The trust policy allows the Lambda service to assume this
#   role at runtime.
# --------------------------------------------------------------------------------
resource "aws_iam_role" "lambda_delete_role" {
  name = "notes-cognito-delete-role"

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
# RESOURCE: aws_iam_role_policy_attachment.lambda_delete_basic
# --------------------------------------------------------------------------------
# Description:
#   Attaches the AWS-managed basic execution policy to grant
#   CloudWatch Logs access for the Lambda function.
# --------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "lambda_delete_basic" {
  role       = aws_iam_role.lambda_delete_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_iam_role_policy.lambda_delete_dynamo
# --------------------------------------------------------------------------------
# Description:
#   Inline IAM policy that allows the Lambda function to delete
#   items from the DynamoDB notes table.
# --------------------------------------------------------------------------------
resource "aws_iam_role_policy" "lambda_delete_dynamo" {
  name = "notes-cognito-delete-dynamo"
  role = aws_iam_role.lambda_delete_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow",
      Action   = ["dynamodb:DeleteItem"],
      Resource = aws_dynamodb_table.notes.arn
    }]
  })
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_lambda_function.lambda_delete
# --------------------------------------------------------------------------------
# Description:
#   Deploys the "delete-note" Lambda function. The function
#   deletes a note in DynamoDB and returns a simple confirmation.
#
# Handler:
#   notes.delete_handler  (code/notes.py)
# --------------------------------------------------------------------------------
resource "aws_lambda_function" "lambda_delete" {
  function_name    = "delete-note-cognito"
  role             = aws_iam_role.lambda_delete_role.arn
  runtime          = "python3.14"
  handler          = "notes.delete_handler"
  filename         = data.archive_file.lambdas_zip.output_path
  source_code_hash = data.archive_file.lambdas_zip.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      NOTES_TABLE_NAME = aws_dynamodb_table.notes.name
    }
  }
}
