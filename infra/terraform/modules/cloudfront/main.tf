terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

locals {
  name_prefix = "${var.project}-${var.env}"
}

# ─────────────────────────────────────────
# WAF Web ACL（CloudFront 用は us-east-1 固定）
# ─────────────────────────────────────────
resource "aws_wafv2_web_acl" "viewer" {
  provider    = aws.us_east_1
  name        = "${local.name_prefix}-viewer-waf"
  description = "OHIF Viewer WAF"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # AWS マネージドルール: 一般的な脅威ブロック
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action { none {} }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # AWS マネージドルール: 既知の不正 IP ブロック
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 20

    override_action { none {} }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-viewer-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

# ─────────────────────────────────────────
# CloudFront OAC（S3 オリジンアクセス制御）
# ─────────────────────────────────────────
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name_prefix}-frontend-oac"
  description                       = "OAC for OHIF Viewer S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ─────────────────────────────────────────
# CloudFront Distribution
# ─────────────────────────────────────────
resource "aws_cloudfront_distribution" "viewer" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "${local.name_prefix} OHIF Viewer"
  web_acl_id          = aws_wafv2_web_acl.viewer.arn
  price_class         = "PriceClass_100"  # 北米 + 欧州のみ（コスト最適化）

  origin {
    domain_name              = var.frontend_bucket_regional_domain
    origin_id                = "S3-${var.frontend_bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id       = "S3-${var.frontend_bucket_name}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    # index.html はキャッシュしない
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # 静的アセット（ハッシュ付きファイル名）は長期キャッシュ
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "S3-${var.frontend_bucket_name}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 31536000
    default_ttl = 31536000
    max_ttl     = 31536000
  }

  # SPA: 404 → index.html にフォールバック
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    # カスタムドメインを使用する場合は以下に切り替える:
    # acm_certificate_arn      = var.acm_certificate_arn
    # ssl_support_method       = "sni-only"
    # minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

# ─────────────────────────────────────────
# S3 バケットポリシー（CloudFront OAC からのみアクセス許可）
# ─────────────────────────────────────────
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = var.frontend_bucket_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${var.frontend_bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.viewer.arn
          }
        }
      }
    ]
  })
}
