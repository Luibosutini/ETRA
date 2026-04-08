locals {
  name_prefix = "${var.project}-${var.env}"
}

# ─────────────────────────────────────────
# 夜間自動停止スケジュール（平日 22:00 JST）
# ─────────────────────────────────────────
resource "aws_scheduler_schedule" "auto_stop" {
  name       = "${local.name_prefix}-auto-stop-analysis"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  # cron は UTC。JST 22:00 = UTC 13:00
  schedule_expression          = "cron(0 13 ? * MON-FRI *)"
  schedule_expression_timezone = "UTC"

  target {
    arn      = var.stop_compute_lambda_arn
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      source    = "scheduled-auto-stop"
      tag_key   = "AutoStop"
      tag_value = "true"
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
  name   = "invoke-stop-lambda"
  role   = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = var.stop_compute_lambda_arn
    }]
  })
}
