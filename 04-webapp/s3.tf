# ================================================================================
# File: s3.tf
# ================================================================================
# Purpose:
#   Upload static SPA assets to the existing public web bucket created by
#   01-backend. This module does NOT create or manage the bucket — it only
#   writes index.html, callback.html, config.json, and favicon.ico to it.
# ================================================================================

variable "web_bucket_name" {
  description = "Existing S3 bucket name hosting the SPA."
  type        = string
}

resource "aws_s3_object" "index_html" {
  bucket        = var.web_bucket_name
  key           = "index.html"
  source        = "${path.module}/index.html"
  content_type  = "text/html"
  etag          = filemd5("${path.module}/index.html")
  cache_control = "no-store, max-age=0"
}

resource "aws_s3_object" "callback_html" {
  bucket        = var.web_bucket_name
  key           = "callback.html"
  source        = "${path.module}/callback.html"
  content_type  = "text/html"
  etag          = filemd5("${path.module}/callback.html")
  cache_control = "no-store, max-age=0"
}

resource "aws_s3_object" "config_json" {
  bucket        = var.web_bucket_name
  key           = "config.json"
  source        = "${path.module}/config.json"
  content_type  = "application/json"
  etag          = filemd5("${path.module}/config.json")
  cache_control = "no-store, max-age=0"
}

resource "aws_s3_object" "favicon" {
  bucket        = var.web_bucket_name
  key           = "favicon.ico"
  source        = "${path.module}/favicon.ico"
  content_type  = "image/x-icon"
  etag          = filemd5("${path.module}/favicon.ico")
  cache_control = "no-store, max-age=0"
}
