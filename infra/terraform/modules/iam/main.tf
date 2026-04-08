locals {
  name_prefix = "${var.project}-${var.env}"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ─────────────────────────────────────────
# Lambda: start_compute
# ─────────────────────────────────────────
resource "aws_iam_role" "lambda_start_compute" {
  name               = "${local.name_prefix}-lambda-start-compute"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_start_compute" {
  name   = "policy"
  role   = aws_iam_role.lambda_start_compute.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:StartInstances", "ec2:DescribeInstances"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Project" = var.project
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface"]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────
# Lambda: stop_compute
# ─────────────────────────────────────────
resource "aws_iam_role" "lambda_stop_compute" {
  name               = "${local.name_prefix}-lambda-stop-compute"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_stop_compute" {
  name   = "policy"
  role   = aws_iam_role.lambda_stop_compute.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:StopInstances", "ec2:DescribeInstances"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Project" = var.project
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface"]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────
# Lambda: status_compute
# ─────────────────────────────────────────
resource "aws_iam_role" "lambda_status_compute" {
  name               = "${local.name_prefix}-lambda-status-compute"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_status_compute" {
  name   = "policy"
  role   = aws_iam_role.lambda_status_compute.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface"]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────
# Lambda: workspace_api
# ─────────────────────────────────────────
resource "aws_iam_role" "lambda_workspace_api" {
  name               = "${local.name_prefix}-lambda-workspace-api"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_workspace_api" {
  name   = "policy"
  role   = aws_iam_role.lambda_workspace_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          var.workspace_bucket_arn,
          "${var.workspace_bucket_arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface"]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────
# Lambda: notify_status
# ─────────────────────────────────────────
resource "aws_iam_role" "lambda_notify_status" {
  name               = "${local.name_prefix}-lambda-notify-status"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_notify_status" {
  name   = "policy"
  role   = aws_iam_role.lambda_notify_status.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = var.notification_topic_arn != "" ? [var.notification_topic_arn] : ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface"]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────
# EC2 解析ノード インスタンスロール
# ─────────────────────────────────────────
resource "aws_iam_role" "ec2_analysis" {
  name               = "${local.name_prefix}-ec2-analysis"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy" "ec2_analysis_workspace" {
  name   = "workspace-access"
  role   = aws_iam_role.ec2_analysis.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          var.workspace_bucket_arn,
          "${var.workspace_bucket_arn}/*"
        ]
      }
    ]
  })
}

# SSM Agent 用マネージドポリシー
resource "aws_iam_role_policy_attachment" "ec2_analysis_ssm" {
  role       = aws_iam_role.ec2_analysis.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_analysis" {
  name = "${local.name_prefix}-ec2-analysis"
  role = aws_iam_role.ec2_analysis.name
}
