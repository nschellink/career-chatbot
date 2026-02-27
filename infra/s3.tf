# S3 bucket for context files (PDFs, summary.txt). Synced to EC2 at boot.
# Created in the provider's region (var.region). If you change region, remove stale
# S3 resources from state first to avoid 301 PermanentRedirect (see DEPLOY.md).
resource "aws_s3_bucket" "context" {
  bucket_prefix = "${var.app_name}-context-"
}

resource "aws_s3_bucket_versioning" "context" {
  bucket = aws_s3_bucket.context.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "context" {
  bucket = aws_s3_bucket.context.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "context" {
  bucket = aws_s3_bucket.context.id

  block_public_acls       = true
  block_public_policy      = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM can read via bucket policy in iam.tf (instance profile + GetObject)
