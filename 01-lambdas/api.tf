# ================================================================================
# File: api.tf
# ================================================================================
# Purpose:
#   Provides REST-style endpoints for the Notes API:
#     - POST   /notes        → Create a new note
#     - GET    /notes        → List all notes
#     - GET    /notes/{id}   → Retrieve a single note
#     - PUT    /notes/{id}   → Update a note
#     - DELETE /notes/{id}   → Delete a note
#
# Notes:
#   - Uses HTTP API (v2) for simplicity and cost efficiency.
#   - Each route integrates directly with a Lambda function.
# ================================================================================

# --------------------------------------------------------------------------------
# RESOURCE: aws_apigatewayv2_api.notes_api
# --------------------------------------------------------------------------------
# Description:
#   Creates an HTTP API that exposes the Notes Lambda endpoints.
#   CORS configuration allows client access during development.
# --------------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "notes_api" {
  name          = "notes-api-cognito"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins  = ["*"] # Restrict to domain in production
    allow_methods  = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers  = ["content-type", "authorization"]
    expose_headers = ["content-type"]
    max_age        = 300
  }
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_apigatewayv2_authorizer.cognito_jwt
# --------------------------------------------------------------------------------
# Description:
#   Configures an HTTP API JWT authorizer that validates Cognito access tokens.
#
# Notes:
#   - The issuer MUST be the Cognito *User Pool issuer* (cognito-idp), not the
#     Hosted UI domain (amazoncognito.com).
#   - API Gateway requires a full URL (must include https://).
#   - Discovery document must exist at:
#       <issuer>/.well-known/openid-configuration
# --------------------------------------------------------------------------------
resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
  api_id          = aws_apigatewayv2_api.notes_api.id
  name            = "cognito-jwt"
  authorizer_type = "JWT"

  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.spa.id]
    issuer   = "https://${aws_cognito_user_pool.this.endpoint}"
  }
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_apigatewayv2_integration.create_note_integration
# --------------------------------------------------------------------------------
# Description:
#   Connects POST /notes route to the create-note Lambda function.
#   Uses AWS_PROXY integration for full event passthrough.
# --------------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "create_note_integration" {
  api_id                 = aws_apigatewayv2_api.notes_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.lambda_create.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_apigatewayv2_integration.list_notes_integration
# --------------------------------------------------------------------------------
# Description:
#   Connects GET /notes route to the list-notes Lambda function.
#   Uses AWS_PROXY integration for full event passthrough.
# --------------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "list_notes_integration" {
  api_id                 = aws_apigatewayv2_api.notes_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.lambda_list.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_apigatewayv2_integration.get_note_integration
# --------------------------------------------------------------------------------
# Description:
#   Connects GET /notes/{id} route to the notes-get Lambda function.
#   Uses AWS_PROXY integration for full event passthrough.
# --------------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "get_note_integration" {
  api_id                 = aws_apigatewayv2_api.notes_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.lambda_get.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_apigatewayv2_integration.update_note_integration
# --------------------------------------------------------------------------------
# Description:
#   Connects PUT /notes/{id} route to the update-note Lambda function.
#   Uses AWS_PROXY integration for full event passthrough.
# --------------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "update_note_integration" {
  api_id                 = aws_apigatewayv2_api.notes_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.lambda_update.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_apigatewayv2_integration.delete_note_integration
# --------------------------------------------------------------------------------
# Description:
#   Connects DELETE /notes/{id} route to the delete-note Lambda function.
#   Uses AWS_PROXY integration for full event passthrough.
# --------------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "delete_note_integration" {
  api_id                 = aws_apigatewayv2_api.notes_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.lambda_delete.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_apigatewayv2_route.create_note_route
# --------------------------------------------------------------------------------
# Description:
#   Defines the POST /notes route mapped to the create integration.
# --------------------------------------------------------------------------------
resource "aws_apigatewayv2_route" "create_note_route" {
  api_id             = aws_apigatewayv2_api.notes_api.id
  route_key          = "POST /notes"
  target             = "integrations/${aws_apigatewayv2_integration.create_note_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_apigatewayv2_route.list_notes_route
# --------------------------------------------------------------------------------
# Description:
#   Defines the GET /notes route mapped to the list integration.
# --------------------------------------------------------------------------------
resource "aws_apigatewayv2_route" "list_notes_route" {
  api_id             = aws_apigatewayv2_api.notes_api.id
  route_key          = "GET /notes"
  target             = "integrations/${aws_apigatewayv2_integration.list_notes_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id

}

# --------------------------------------------------------------------------------
# RESOURCE: aws_apigatewayv2_route.get_note_route
# --------------------------------------------------------------------------------
# Description:
#   Defines the GET /notes/{id} route mapped to the get integration.
# --------------------------------------------------------------------------------
resource "aws_apigatewayv2_route" "get_note_route" {
  api_id             = aws_apigatewayv2_api.notes_api.id
  route_key          = "GET /notes/{id}"
  target             = "integrations/${aws_apigatewayv2_integration.get_note_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_apigatewayv2_route.update_note_route
# --------------------------------------------------------------------------------
# Description:
#   Defines the PUT /notes/{id} route mapped to the update integration.
# --------------------------------------------------------------------------------
resource "aws_apigatewayv2_route" "update_note_route" {
  api_id             = aws_apigatewayv2_api.notes_api.id
  route_key          = "PUT /notes/{id}"
  target             = "integrations/${aws_apigatewayv2_integration.update_note_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_apigatewayv2_route.delete_note_route
# --------------------------------------------------------------------------------
# Description:
#   Defines the DELETE /notes/{id} route mapped to the delete integration.
# --------------------------------------------------------------------------------
resource "aws_apigatewayv2_route" "delete_note_route" {
  api_id             = aws_apigatewayv2_api.notes_api.id
  route_key          = "DELETE /notes/{id}"
  target             = "integrations/${aws_apigatewayv2_integration.delete_note_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_apigatewayv2_stage.notes_stage
# --------------------------------------------------------------------------------
# Description:
#   Creates the default stage for automatic API deployment.
# --------------------------------------------------------------------------------
resource "aws_apigatewayv2_stage" "notes_stage" {
  api_id      = aws_apigatewayv2_api.notes_api.id
  name        = "$default"
  auto_deploy = true
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_lambda_permission.allow_create_invoke
# --------------------------------------------------------------------------------
# Description:
#   Grants API Gateway permission to invoke the create-note Lambda.
# --------------------------------------------------------------------------------
resource "aws_lambda_permission" "allow_create_invoke" {
  statement_id  = "AllowAPIGatewayInvokeCreate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_create.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.notes_api.execution_arn}/*/*"
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_lambda_permission.allow_list_invoke
# --------------------------------------------------------------------------------
# Description:
#   Grants API Gateway permission to invoke the list-notes Lambda.
# --------------------------------------------------------------------------------
resource "aws_lambda_permission" "allow_list_invoke" {
  statement_id  = "AllowAPIGatewayInvokeList"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_list.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.notes_api.execution_arn}/*/*"
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_lambda_permission.allow_get_invoke
# --------------------------------------------------------------------------------
# Description:
#   Grants API Gateway permission to invoke the notes-get Lambda.
# --------------------------------------------------------------------------------
resource "aws_lambda_permission" "allow_get_invoke" {
  statement_id  = "AllowAPIGatewayInvokeGet"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_get.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.notes_api.execution_arn}/*/*"
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_lambda_permission.allow_update_invoke
# --------------------------------------------------------------------------------
# Description:
#   Grants API Gateway permission to invoke the update-note Lambda.
# --------------------------------------------------------------------------------
resource "aws_lambda_permission" "allow_update_invoke" {
  statement_id  = "AllowAPIGatewayInvokeUpdate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_update.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.notes_api.execution_arn}/*/*"
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_lambda_permission.allow_delete_invoke
# --------------------------------------------------------------------------------
# Description:
#   Grants API Gateway permission to invoke the delete-note Lambda.
# --------------------------------------------------------------------------------
resource "aws_lambda_permission" "allow_delete_invoke" {
  statement_id  = "AllowAPIGatewayInvokeDelete"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_delete.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.notes_api.execution_arn}/*/*"
}

# # --------------------------------------------------------------------------------
# # OUTPUT: notes_api_endpoint (optional)
# # --------------------------------------------------------------------------------
# output "notes_api_endpoint" {
#    description = "Invoke URL for the Notes API Gateway"
#    value       = aws_apigatewayv2_stage.notes_stage.invoke_url
# }
