# ================================================================================
# File: s3.tf
# ================================================================================
# Purpose:
#   Creates the two S3 buckets used by the cartoonify service:
#     1. web_bucket   — public static site hosting for the SPA
#     2. media_bucket — private storage for uploaded originals and generated
#                       cartoons, accessed only through presigned URLs
#
#   Media bucket has a 7-day lifecycle rule on the originals/ and cartoons/
#   prefixes that matches the DynamoDB TTL.
# ================================================================================

# --------------------------------------------------------------------------------
# WEB BUCKET (public SPA hosting)
# --------------------------------------------------------------------------------
resource "aws_s3_bucket" "web_bucket" {
  bucket        = "${var.name}-web-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "web_public_access" {
  bucket                  = aws_s3_bucket.web_bucket.id
  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "web_public_read" {
  bucket = aws_s3_bucket.web_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "AllowPublicRead",
      Effect    = "Allow",
      Principal = "*",
      Action    = "s3:GetObject",
      Resource  = "${aws_s3_bucket.web_bucket.arn}/*"
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.web_public_access]
}

# --------------------------------------------------------------------------------
# MEDIA BUCKET (private, CORS + lifecycle)
# --------------------------------------------------------------------------------
resource "aws_s3_bucket" "media_bucket" {
  bucket        = "${var.name}-media-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "media_block_public" {
  bucket                  = aws_s3_bucket.media_bucket.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Browser uploads (presigned POST) require CORS on the media bucket.
resource "aws_s3_bucket_cors_configuration" "media_cors" {
  bucket = aws_s3_bucket.media_bucket.id

  cors_rule {
    allowed_methods = ["GET", "POST", "PUT"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "media_lifecycle" {
  bucket = aws_s3_bucket.media_bucket.id

  rule {
    id     = "expire-originals"
    status = "Enabled"

    filter {
      prefix = "originals/"
    }

    expiration {
      days = 7
    }
  }

  rule {
    id     = "expire-cartoons"
    status = "Enabled"

    filter {
      prefix = "cartoons/"
    }

    expiration {
      days = 7
    }
  }
}

# --------------------------------------------------------------------------------
# OUTPUTS
# --------------------------------------------------------------------------------
output "web_bucket_name" {
  value = aws_s3_bucket.web_bucket.bucket
}

output "media_bucket_name" {
  value = aws_s3_bucket.media_bucket.bucket
}

output "media_bucket_arn" {
  value = aws_s3_bucket.media_bucket.arn
}
