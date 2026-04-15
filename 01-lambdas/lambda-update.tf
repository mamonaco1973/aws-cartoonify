# ================================================================================
# File: lambda_update.tf
# ================================================================================
# Purpose:
#   Deploys the "Update Note" Lambda function that updates an existing
#   note in the DynamoDB notes table. This function is intended to be
#   invoked by an API Gateway route such as PUT /notes/{id}.
#
# Notes:
#   - Uses Python 3.11 runtime.
#   - Updates items in the DynamoDB "notes" table defined in dynamodb.tf.
# ================================================================================

# --------------------------------------------------------------------------------
# RESOURCE: aws_iam_role.lambda_update_role
# --------------------------------------------------------------------------------
# Description:
#   IAM role assumed by the Lambda function during execution.
#   The trust policy allows the Lambda service to assume this
#   role at runtime.
# --------------------------------------------------------------------------------
resource "aws_iam_role" "lambda_update_role" {
  name = "notes-cognito-update-role"

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
# RESOURCE: aws_iam_role_policy_attachment.lambda_update_basic
# --------------------------------------------------------------------------------
# Description:
#   Attaches the AWS-managed basic execution policy to grant
#   CloudWatch Logs access for the Lambda function.
# --------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "lambda_update_basic" {
  role       = aws_iam_role.lambda_update_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_iam_role_policy.lambda_update_dynamo
# --------------------------------------------------------------------------------
# Description:
#   Inline IAM policy that allows the Lambda function to update
#   items in the DynamoDB notes table.
# --------------------------------------------------------------------------------
resource "aws_iam_role_policy" "lambda_update_dynamo" {
  name = "notes-cognito-update-dynamo"
  role = aws_iam_role.lambda_update_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow",
      Action   = ["dynamodb:UpdateItem"],
      Resource = aws_dynamodb_table.notes.arn
    }]
  })
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_lambda_function.lambda_update
# --------------------------------------------------------------------------------
# Description:
#   Deploys the "update-note" Lambda function. The function
#   updates title and note fields in DynamoDB and returns the
#   updated item.
#
# Handler:
#   notes.update_handler  (code/notes.py)
# --------------------------------------------------------------------------------
resource "aws_lambda_function" "lambda_update" {
  function_name    = "update-note-cognito"
  role             = aws_iam_role.lambda_update_role.arn
  runtime          = "python3.14"
  handler          = "notes.update_handler"
  filename         = data.archive_file.lambdas_zip.output_path
  source_code_hash = data.archive_file.lambdas_zip.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      NOTES_TABLE_NAME = aws_dynamodb_table.notes.name
    }
  }
}
