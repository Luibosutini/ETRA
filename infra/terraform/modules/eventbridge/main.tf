locals {
  name_prefix = "${var.project}-${var.env}"
}

# ─────────────────────────────────────────
# cleanup_compute スケジュール（15 分ごと）
# CPU アイドル検知 + 長期停止インスタンスの terminate
# ─────────────────────────────────────────
resource "aws_scheduler_schedule" "cleanup_compute" {
  name       = "${local.name_prefix}-cleanup-compute"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "rate(15 minutes)"
  schedule_expression_timezone = "UTC"

  target {
    arn      = var.cleanup_compute_lambda_arn
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      source = "scheduled-cleanup"
    })
  }
}

# ─────────────────────────────────────────
# EventBridge Scheduler 実行ロール
# ─────────────────────────────────────────
resource "aws_iam_role" "scheduler" {
  name = "${local.name_prefix}-eventbridge-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "invoke-cleanup-lambda"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = var.cleanup_compute_lambda_arn
    }]
  })
}
