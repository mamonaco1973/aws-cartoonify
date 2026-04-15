# ================================================================================================
# Variables
# ================================================================================================

variable "name" {
  type    = string
  default = "notes"
}

locals {
  spa_origin = format(
    "https://%s.s3.%s.amazonaws.com",
    aws_s3_bucket.web_bucket.bucket,
    data.aws_region.current.id
  )
}

resource "random_id" "suffix" {
  byte_length = 3
}

# ================================================================================================
# Cognito User Pool (email/password)
# ================================================================================================

resource "aws_cognito_user_pool" "this" {
  name = "${var.name}-user-pool"

  # Users sign in with email.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Optional: basic password policy (adjust as you like)
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

# ================================================================================================
# Hosted UI Domain (AWS-provided)
# ================================================================================================

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.name}-auth-${random_id.suffix.hex}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# ================================================================================================
# App Client (no secret for SPA)
# ================================================================================================

resource "aws_cognito_user_pool_client" "spa" {
  name         = "${var.name}-spa-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false

  # Enable SRP auth (client-side username/password without storing secret)
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  # Hosted UI / OAuth (recommended even for "simple email auth" in a SPA)
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]

  supported_identity_providers = ["COGNITO"]

  callback_urls = ["${local.spa_origin}/callback.html"]
  logout_urls   = ["${local.spa_origin}/index.html"]
}

# ================================================================================================
# Outputs
# ================================================================================================

# output "user_pool_id" {
#   value = aws_cognito_user_pool.this.id
# }

# output "user_pool_client_id" {
#   value = aws_cognito_user_pool_client.spa.id
# }

# output "hosted_ui_base" {
#   value = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${var.region}.amazoncognito.com"
# }

# output "hosted_ui_login_url" {
#   value = join("", [
#     "https://", aws_cognito_user_pool_domain.this.domain, ".auth.", var.region, ".amazoncognito.com",
#     "/oauth2/authorize",
#     "?client_id=", aws_cognito_user_pool_client.spa.id,
#     "&response_type=code",
#     "&scope=openid+email+profile",
#     "&redirect_uri=", urlencode("${var.spa_origin}/index.html")
#   ])
# }

# output "hosted_ui_logout_url" {
#   value = join("", [
#     "https://", aws_cognito_user_pool_domain.this.domain, ".auth.", var.region, ".amazoncognito.com",
#     "/logout",
#     "?client_id=", aws_cognito_user_pool_client.spa.id,
#     "&logout_uri=", urlencode("${var.spa_origin}/index.html")
#   ])
# }

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.this.domain
}

output "app_client_id" {
  value = aws_cognito_user_pool_client.spa.id
}
