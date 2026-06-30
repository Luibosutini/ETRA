locals {
  name_prefix = "${var.project}-${var.env}"

  functions = {
    start_compute   = { role_arn = var.role_arns.start_compute, handler = "start_compute.handler" }
    stop_compute    = { role_arn = var.role_arns.stop_compute, handler = "stop_compute.handler" }
    status_compute  = { role_arn = var.role_arns.status_compute, handler = "status_compute.handler" }
    workspace_api   = { role_arn = var.role_arns.workspace_api, handler = "workspace_api.handler" }
    notify_status   = { role_arn = var.role_arns.notify_status, handler = "notify_status.handler" }
    admin_api       = { role_arn = var.role_arns.admin_api, handler = "admin_api.handler" }
    logs_api        = { role_arn = var.role_arns.logs_api, handler = "logs_api.handler" }
    cleanup_compute = { role_arn = var.role_arns.cleanup_compute, handler = "cleanup_compute.handler" }
    connect_api     = { role_arn = var.role_arns.connect_api, handler = "connect_api.handler" }
    restart_jupyter = { role_arn = var.role_arns.restart_jupyter, handler = "restart_jupyter.handler" }
    dicom_api       = { role_arn = var.role_arns.dicom_api, handler = "dicom_api.handler" }
  }

  # VPC 内から到達できない AWS エンドポイントを使う関数は VPC 外に配置する:
  # - admin_api / logs_api: Cognito / CloudWatch Logs はパブリックエンドポイント経由
  # - cleanup_compute: CloudWatch Metrics (GetMetricStatistics) の VPC エンドポイントなし
  # - connect_api: STS はパブリックエンドポイントのみ（PrivateLink 非対応リージョンあり）
  # - notify_status: SNS のみ使用。VPC 内リソースへのアクセスなし → VPC 外で十分
  # restart_jupyter: SSM SendCommand API はパブリックエンドポイント。VPC 外で十分
  # - dicom_api: HealthImaging (medical-imaging) の VPC エンドポイントなし → VPC 外に配置
  no_vpc_functions = toset(["admin_api", "logs_api", "cleanup_compute", "connect_api", "notify_status", "restart_jupyter", "dicom_api"])
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
      contains(["start_compute", "stop_compute", "status_compute", "cleanup_compute"], each.key) ? {
        ANALYSIS_INSTANCE_TAG_KEY   = "Project"
        ANALYSIS_INSTANCE_TAG_VALUE = var.project
      } : {},
      each.key == "start_compute" ? {
        LAUNCH_TEMPLATE_ID = var.launch_template_id
      } : {},
      each.key == "cleanup_compute" ? {
        IDLE_CPU_THRESHOLD     = "5.0"
        IDLE_DURATION_MINUTES  = "120"
        STOPPED_DAYS_THRESHOLD = "7"
      } : {},
      each.key == "workspace_api" ? {
        WORKSPACE_BUCKET = var.workspace_bucket_name
      } : {},
      each.key == "notify_status" ? {
        NOTIFICATION_TOPIC_ARN = var.notification_topic_arn
      } : {},
      each.key == "admin_api" ? {
        USER_POOL_ID = var.cognito_user_pool_id
      } : {},
      each.key == "logs_api" ? {
        LOG_GROUP_PREFIX = "/aws/lambda/${var.project}-${var.env}-"
      } : {},
      each.key == "connect_api" ? {
        SSM_CONNECT_ROLE_ARN = var.ssm_connect_role_arn
      } : {},
      contains(["restart_jupyter"], each.key) ? {
        ANALYSIS_INSTANCE_TAG_KEY   = "Project"
        ANALYSIS_INSTANCE_TAG_VALUE = var.project
      } : {},
      each.key == "dicom_api" ? {
        DATASTORE_ID = var.healthimaging_datastore_id
      } : {}
    )
  }

  dynamic "vpc_config" {
    for_each = contains(local.no_vpc_functions, each.key) ? [] : [1]
    content {
      subnet_ids         = var.private_subnet_ids
      security_group_ids = [var.lambda_sg_id]
    }
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
