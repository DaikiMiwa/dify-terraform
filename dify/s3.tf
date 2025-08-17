# ------------------------------------------------
# Settings for S3
# ------------------------------------------------
resource "aws_s3_bucket" "dify_data" {
  bucket        = "dify-data-${local.base_name}-001"
  force_destroy = true

  tags = merge(
    var.default_tags,
    {
      Name = "s3-bucket-${local.base_name}-dify-data-001"
    }
  )
}

# Block public access to meets security standards in ACN
resource "aws_s3_bucket_public_access_block" "dify_data" {
  bucket = aws_s3_bucket.dify_data.id

  block_public_acls       = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  block_public_policy     = true
}

# Apply 
resource "aws_s3_bucket_server_side_encryption_configuration" "dify_data" {
  bucket = aws_s3_bucket.dify_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "dify_data" {
  # HTTP拒否（TLS必須）
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.dify_data.arn, "${aws_s3_bucket.dify_data.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "dify_data" {
  bucket = aws_s3_bucket.dify_data.id
  policy = data.aws_iam_policy_document.dify_data.json
  depends_on = [
    aws_s3_bucket_public_access_block.dify_data,
    aws_s3_bucket_server_side_encryption_configuration.dify_data
  ]
}

# s3 endpoint for VPC
# resource "aws_vpc_endpoint" "s3" {
#   vpc_id       = aws_vpc.this.id
#   service_name = "com.amazonaws.${var.region}.s3"
# 
#   route_table_ids = [
# 
#   ]
# }

