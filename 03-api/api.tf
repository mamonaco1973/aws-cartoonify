# ================================================================================
# File: api.tf
# ================================================================================
# Purpose:
#   HTTP API (v2) with a Cognito JWT authorizer in front of every route.
#
#     POST   /upload-url           → upload_url Lambda
#     POST   /generate             → submit Lambda
#     GET    /result/{job_id}      → result Lambda
#     GET    /history              → history Lambda
#     DELETE /history/{job_id}     → delete Lambda
# ================================================================================

resource "aws_apigatewayv2_api" "api" {
  name          = "${var.name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins  = ["*"]   # Tighten post-deploy for production use
    allow_methods  = ["GET", "POST", "DELETE", "OPTIONS"]
    allow_headers  = ["content-type", "authorization"]
    expose_headers = ["content-type"]
    max_age        = 300
  }
}

resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
  api_id           = aws_apigatewayv2_api.api.id
  name             = "cognito-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [local.app_client_id]
    issuer   = "https://${data.aws_cognito_user_pool.this.endpoint}"
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

# --------------------------------------------------------------------------------
# Route table — one integration + one route per Lambda.
# Each integration uses AWS_PROXY payload v2.0.
# --------------------------------------------------------------------------------
locals {
  routes = {
    upload_url = {
      method        = "POST"
      path          = "/upload-url"
      function_name = aws_lambda_function.upload_url.function_name
      invoke_arn    = aws_lambda_function.upload_url.invoke_arn
    }
    submit = {
      method        = "POST"
      path          = "/generate"
      function_name = aws_lambda_function.submit.function_name
      invoke_arn    = aws_lambda_function.submit.invoke_arn
    }
    result = {
      method        = "GET"
      path          = "/result/{job_id}"
      function_name = aws_lambda_function.result.function_name
      invoke_arn    = aws_lambda_function.result.invoke_arn
    }
    history = {
      method        = "GET"
      path          = "/history"
      function_name = aws_lambda_function.history.function_name
      invoke_arn    = aws_lambda_function.history.invoke_arn
    }
    delete = {
      method        = "DELETE"
      path          = "/history/{job_id}"
      function_name = aws_lambda_function.delete.function_name
      invoke_arn    = aws_lambda_function.delete.invoke_arn
    }
  }
}

resource "aws_apigatewayv2_integration" "route" {
  for_each = local.routes

  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = each.value.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "route" {
  for_each = local.routes

  api_id             = aws_apigatewayv2_api.api.id
  route_key          = "${each.value.method} ${each.value.path}"
  target             = "integrations/${aws_apigatewayv2_integration.route[each.key].id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id
}

resource "aws_lambda_permission" "route_invoke" {
  for_each = local.routes

  statement_id  = "AllowAPIGatewayInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# --------------------------------------------------------------------------------
# OUTPUTS
# --------------------------------------------------------------------------------
output "api_endpoint" {
  value = aws_apigatewayv2_api.api.api_endpoint
}
