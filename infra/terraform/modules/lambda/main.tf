locals {
  name_prefix = "${var.project}-${var.env}"

  functions = {
    start_compute  = { role_arn = var.role_arns.start_compute,  handler = "start_compute.handler" }
    stop_compute   = { role_arn = var.role_arns.stop_compute,   handler = "stop_compute.handler" }
    status_compute = { role_arn = var.role_arns.status_compute, handler = "status_compute.handler" }
    workspace_api  = { role_arn = var.role_arns.workspace_api,  handler = "workspace_api.handler" }
    notify_status  = { role_arn = var.role_arns.notify_status,  handler = "notify_status.handler" }
  }
}

# ─────────────────────────────────────────
# Lambda 関数（5 つ）
# ─────────────────────────────────────────
resource "aws_lambda_function" "this" {
  for_each = local.functions

  function_name = "${local.name_prefix}-${each.key}"
  role          = each.value.role_arn
  handler       = each.value.handler
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 256

  filename         = "${path.module}/placeholder.zip"
  source_code_hash = filebase64sha256("${path.module}/placeholder.zip")

  environment {
    variables = merge(
      {
        ENV     = var.env
        PROJECT = var.project
        REGION  = var.region
      },
      each.key == "start_compute" || each.key == "stop_compute" || each.key == "status_compute" ? {
        ANALYSIS_INSTANCE_TAG_KEY   = "Project"
        ANALYSIS_INSTANCE_TAG_VALUE = var.project
      } : {},
      each.key == "workspace_api" ? {
        WORKSPACE_BUCKET = var.workspace_bucket_name
      } : {},
      each.key == "notify_status" ? {
        NOTIFICATION_TOPIC_ARN = var.notification_topic_arn
      } : {}
    )
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_sg_id]
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

# ─────────────────────────────────────────
# CloudWatch ロググループ
# ─────────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = local.functions
  name              = "/aws/lambda/${local.name_prefix}-${each.key}"
  retention_in_days = 30
}
