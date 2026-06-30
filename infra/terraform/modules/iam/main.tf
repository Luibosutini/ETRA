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
  name = "policy"
  role = aws_iam_role.lambda_start_compute.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:StartInstances"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Project" = var.project
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        # run_instances はリソース条件が使えないため * で制限しリクエスト条件で絞る
        Effect   = "Allow"
        Action   = ["ec2:RunInstances"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = "RunInstances"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeLaunchTemplates", "ec2:DescribeLaunchTemplateVersions"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.ec2_analysis.arn
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
  name = "policy"
  role = aws_iam_role.lambda_stop_compute.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:StopInstances"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Project" = var.project
          }
        }
      },
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
# Lambda: status_compute
# ─────────────────────────────────────────
resource "aws_iam_role" "lambda_status_compute" {
  name               = "${local.name_prefix}-lambda-status-compute"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_status_compute" {
  name = "policy"
  role = aws_iam_role.lambda_status_compute.id
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
        Action   = ["ssm:DescribeInstanceInformation"]
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
  name = "policy"
  role = aws_iam_role.lambda_workspace_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
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
  name = "policy"
  role = aws_iam_role.lambda_notify_status.id
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
# Lambda: admin_api
# ─────────────────────────────────────────
resource "aws_iam_role" "lambda_admin_api" {
  name               = "${local.name_prefix}-lambda-admin-api"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_admin_api" {
  name = "policy"
  role = aws_iam_role.lambda_admin_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:ListUsers",
          "cognito-idp:AdminListGroupsForUser",
          "cognito-idp:AdminAddUserToGroup",
          "cognito-idp:AdminRemoveUserFromGroup",
        ]
        Resource = var.cognito_user_pool_arn
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:TerminateInstances"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Project" = var.project
          }
        }
      },
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
# Lambda: logs_api
# ─────────────────────────────────────────
resource "aws_iam_role" "lambda_logs_api" {
  name               = "${local.name_prefix}-lambda-logs-api"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_logs_api" {
  name = "policy"
  role = aws_iam_role.lambda_logs_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:FilterLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
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
# Lambda: cleanup_compute
# ─────────────────────────────────────────
resource "aws_iam_role" "lambda_cleanup_compute" {
  name               = "${local.name_prefix}-lambda-cleanup-compute"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_cleanup_compute" {
  name = "policy"
  role = aws_iam_role.lambda_cleanup_compute.id
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
        Action   = ["ec2:StopInstances", "ec2:TerminateInstances"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Project" = var.project
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricStatistics"]
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
# Lambda: restart_jupyter
# ─────────────────────────────────────────
resource "aws_iam_role" "lambda_restart_jupyter" {
  name               = "${local.name_prefix}-lambda-restart-jupyter"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_restart_jupyter" {
  name = "policy"
  role = aws_iam_role.lambda_restart_jupyter.id
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
        Action   = ["ssm:SendCommand"]
        Resource = ["arn:aws:ssm:*::document/AWS-RunShellScript"]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:SendCommand"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ssm:resourceTag/Project" = var.project
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetCommandInvocation", "ssm:DescribeInstanceInformation"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ─────────────────────────────────────────
# Lambda: connect_api
# ─────────────────────────────────────────
resource "aws_iam_role" "lambda_connect_api" {
  name               = "${local.name_prefix}-lambda-connect-api"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_connect_api" {
  name = "policy"
  role = aws_iam_role.lambda_connect_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = aws_iam_role.ssm_connect_user.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ─────────────────────────────────────────
# Lambda: dicom_api
# ─────────────────────────────────────────
resource "aws_iam_role" "lambda_dicom_api" {
  name               = "${local.name_prefix}-lambda-dicom-api"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_dicom_api" {
  name = "policy"
  role = aws_iam_role.lambda_dicom_api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["medical-imaging:SearchImageSets"]
        Resource = [
          var.healthimaging_datastore_arn,
          "${var.healthimaging_datastore_arn}/imageset/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ─────────────────────────────────────────
# SSM connect user ロール（ユーザー一時クレデンシャル用）
# ─────────────────────────────────────────
resource "aws_iam_role" "ssm_connect_user" {
  name = "${local.name_prefix}-ssm-connect-user"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = aws_iam_role.lambda_connect_api.arn }
    }]
  })
}

resource "aws_iam_role_policy" "ssm_connect_user" {
  name = "policy"
  role = aws_iam_role.ssm_connect_user.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # SSM ドキュメントへのアクセス（AWS 管理ドキュメントはタグを持たないため条件なし）
        Effect = "Allow"
        Action = ["ssm:StartSession"]
        Resource = [
          "arn:aws:ssm:*::document/AWS-StartPortForwardingSession",
          "arn:aws:ssm:*::document/AWS-StartSSHSession",
          "arn:aws:ssm:*:*:document/SSM-SessionManagerRunShell",
        ]
      },
      {
        # EC2 インスタンスへのアクセス（プロジェクトタグで対象を限定）
        Effect   = "Allow"
        Action   = ["ssm:StartSession"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ssm:resourceTag/Project" = var.project
          }
        }
      },
      {
        # セッション操作（セッションリソースにはタグがないため条件なし）
        Effect = "Allow"
        Action = [
          "ssm:TerminateSession",
          "ssm:ResumeSession",
          "ssm:DescribeSessions",
          "ssm:GetConnectionStatus"
        ]
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
  name = "workspace-access"
  role = aws_iam_role.ec2_analysis.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          var.workspace_bucket_arn,
          "${var.workspace_bucket_arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeTags"]
        Resource = "*"
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
