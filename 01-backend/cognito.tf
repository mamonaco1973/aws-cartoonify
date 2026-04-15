# ================================================================================
# File: cognito.tf
# ================================================================================
# Purpose:
#   Cognito User Pool + Hosted UI + SPA app client (no secret, PKCE).
#   Self-service email sign-up is enabled; email is the sign-in attribute.
#
#   The app client callback is the web bucket's callback.html, derived from
#   the bucket resource so it stays in sync.
# ================================================================================

locals {
  spa_origin = format(
    "https://%s.s3.%s.amazonaws.com",
    aws_s3_bucket.web_bucket.bucket,
    data.aws_region.current.id
  )
}

# --------------------------------------------------------------------------------
# USER POOL
# --------------------------------------------------------------------------------
resource "aws_cognito_user_pool" "this" {
  name = "${var.name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

# --------------------------------------------------------------------------------
# HOSTED UI DOMAIN
# --------------------------------------------------------------------------------
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.name}-auth-${random_id.suffix.hex}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# --------------------------------------------------------------------------------
# APP CLIENT (SPA, PKCE, no secret)
# --------------------------------------------------------------------------------
resource "aws_cognito_user_pool_client" "spa" {
  name         = "${var.name}-spa-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]

  supported_identity_providers = ["COGNITO"]

  callback_urls = ["${local.spa_origin}/callback.html"]
  logout_urls   = ["${local.spa_origin}/index.html"]
}

# --------------------------------------------------------------------------------
# OUTPUTS
# --------------------------------------------------------------------------------
output "cognito_domain" {
  value = aws_cognito_user_pool_domain.this.domain
}

output "app_client_id" {
  value = aws_cognito_user_pool_client.spa.id
}

output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "user_pool_endpoint" {
  value = aws_cognito_user_pool.this.endpoint
}
