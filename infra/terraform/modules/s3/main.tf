locals {
  name_prefix = "${var.project}-${var.env}"
}

# ─────────────────────────────────────────
# 共通モジュール（バケット作成 + 設定）
# ─────────────────────────────────────────
resource "aws_s3_bucket" "workspace" {
  bucket = "${local.name_prefix}-workspace"
}

resource "aws_s3_bucket" "frontend" {
  bucket = "${local.name_prefix}-frontend"
}

resource "aws_s3_bucket" "logs" {
  bucket = "${local.name_prefix}-access-logs"
}

# ─────────────────────────────────────────
# バージョニング
# ─────────────────────────────────────────
resource "aws_s3_bucket_versioning" "workspace" {
  bucket = aws_s3_bucket.workspace.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration { status = "Enabled" }
}

# ─────────────────────────────────────────
# 暗号化（SSE-S3）
# ─────────────────────────────────────────
resource "aws_s3_bucket_server_side_encryption_configuration" "workspace" {
  bucket = aws_s3_bucket.workspace.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# ─────────────────────────────────────────
# パブリックアクセスブロック
# ─────────────────────────────────────────
resource "aws_s3_bucket_public_access_block" "workspace" {
  bucket                  = aws_s3_bucket.workspace.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─────────────────────────────────────────
# アクセスログ（workspace → logs バケット）
# ─────────────────────────────────────────
resource "aws_s3_bucket_logging" "workspace" {
  bucket        = aws_s3_bucket.workspace.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "workspace/"
}

# ─────────────────────────────────────────
# Lifecycle: shared/dropbox/ を 24 時間で削除
# ─────────────────────────────────────────
resource "aws_s3_bucket_lifecycle_configuration" "workspace" {
  bucket = aws_s3_bucket.workspace.id

  rule {
    id     = "dropbox-ttl-24h"
    status = "Enabled"

    filter {
      prefix = "shared/dropbox/"
    }

    expiration {
      days = 1
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}
