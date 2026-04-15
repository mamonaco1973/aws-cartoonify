# ==============================================================================
# File: s3.tf
# ==============================================================================
# Purpose:
#   Upload static web assets to an existing S3 bucket.
#
# Notes:
#   - This module does NOT create or manage the bucket.
#   - Bucket name is provided as an input variable.
# ==============================================================================

# ------------------------------------------------------------------------------
# Variable: web_bucket_name
# ------------------------------------------------------------------------------
variable "web_bucket_name" {
  description = "Existing S3 bucket name for web assets."
  type        = string
}

# ------------------------------------------------------------------------------
# Upload: index.html
# ------------------------------------------------------------------------------
resource "aws_s3_object" "index_html" {
  bucket        = var.web_bucket_name
  key           = "index.html"
  source        = "${path.module}/index.html"
  content_type  = "text/html"
  etag          = filemd5("${path.module}/index.html")
  cache_control = "no-store, max-age=0"
}

# ------------------------------------------------------------------------------
# Upload: config.json
# ------------------------------------------------------------------------------
resource "aws_s3_object" "config_json" {
  bucket        = var.web_bucket_name
  key           = "config.json"
  source        = "${path.module}/config.json"
  content_type  = "application/json"
  etag          = filemd5("${path.module}/config.json")
  cache_control = "no-store, max-age=0"
}

# ------------------------------------------------------------------------------
# Upload: callback.html
# ------------------------------------------------------------------------------
resource "aws_s3_object" "callback_html" {
  bucket        = var.web_bucket_name
  key           = "callback.html"
  source        = "${path.module}/callback.html"
  content_type  = "text/html"
  etag          = filemd5("${path.module}/callback.html")
  cache_control = "no-store, max-age=0"
}

# ------------------------------------------------------------------------------
# Upload: favicon.ico
# ------------------------------------------------------------------------------
resource "aws_s3_object" "favicon" {
  bucket        = var.web_bucket_name
  key           = "favicon.ico"
  source        = "${path.module}/favicon.ico"
  content_type  = "image/x-icon"
  etag          = filemd5("${path.module}/favicon.ico")
  cache_control = "no-store, max-age=0"
}

# # ------------------------------------------------------------------------------
# # Output: website_https_url
# # ------------------------------------------------------------------------------
# output "website_https_url" {
#   description = "HTTPS URL to index.html (regional S3 REST endpoint)."
#   value = format(
#     "https://%s.s3.%s.amazonaws.com/index.html",
#     var.web_bucket_name,
#     data.aws_region.current.id
#   )
# }