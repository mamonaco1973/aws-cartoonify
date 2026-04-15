# ================================================================================
# File: s3.tf
# ================================================================================
# Purpose:
#   Creates an Amazon S3 bucket for hosting a static website that
#   serves the KeyGen web client. The bucket and policy allow
#   public read access to the index.html file.
#
# Notes:
#   - A random suffix ensures globally unique bucket names.
#   - Public access must remain open for static web hosting.
# ================================================================================

# --------------------------------------------------------------------------------
# RESOURCE: random_id.suffix
# --------------------------------------------------------------------------------
# Description:
#   Generates a random 4-byte hexadecimal suffix to guarantee a
#   unique S3 bucket name.
# --------------------------------------------------------------------------------
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_s3_bucket.web_bucket
# --------------------------------------------------------------------------------
# Description:
#   Creates the S3 bucket that stores website content. The name
#   includes a random suffix to prevent naming conflicts.
# --------------------------------------------------------------------------------
resource "aws_s3_bucket" "web_bucket" {
  bucket = "cnotes-web-${random_id.bucket_suffix.hex}"
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_s3_bucket_public_access_block.allow_public
# --------------------------------------------------------------------------------
# Description:
#   Disables S3 Block Public Access settings to permit a public
#   read policy on the website bucket.
# --------------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "allow_public" {
  bucket                  = aws_s3_bucket.web_bucket.id
  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

# --------------------------------------------------------------------------------
# RESOURCE: aws_s3_bucket_policy.public_policy
# --------------------------------------------------------------------------------
# Description:
#   Applies a bucket policy that grants public read (GET) access
#   to all objects within the S3 bucket.
# --------------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "public_policy" {
  bucket = aws_s3_bucket.web_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowPublicRead",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.web_bucket.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.allow_public]
}
