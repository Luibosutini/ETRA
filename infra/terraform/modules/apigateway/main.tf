locals {
  name_prefix = "${var.project}-${var.env}"
}

# ─────────────────────────────────────────
# HTTP API (API Gateway v2)
# ─────────────────────────────────────────
resource "aws_apigatewayv2_api" "this" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
  description   = "ETRA Analysis Portal API"

  cors_configuration {
    allow_headers = ["Authorization", "Content-Type"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_origins = var.allowed_origins
    max_age       = 300
  }

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

# ─────────────────────────────────────────
# Cognito JWT Authorizer
# ─────────────────────────────────────────
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${local.name_prefix}-cognito-jwt"

  jwt_configuration {
    audience = [var.cognito_client_id]
    issuer   = "https://cognito-idp.us-east-1.amazonaws.com/${var.cognito_user_pool_id}"
  }
}

# ─────────────────────────────────────────
# CloudWatch Logs
# ─────────────────────────────────────────
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/${local.name_prefix}-api"
  retention_in_days = 30

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

# ─────────────────────────────────────────
# Stage ($default)
# ─────────────────────────────────────────
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      sourceIp       = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
    })
  }

  default_route_settings {
    detailed_metrics_enabled = true
    throttling_burst_limit   = 100
    throttling_rate_limit    = 50
  }

  tags = {
    Project     = var.project
    Environment = var.env
  }
}

# ─────────────────────────────────────────
# Lambda Integrations
# ─────────────────────────────────────────
resource "aws_apigatewayv2_integration" "admin_api" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arns.admin_api
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "logs_api" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arns.logs_api
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "start_compute" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arns.start_compute
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "stop_compute" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arns.stop_compute
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "status_compute" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arns.status_compute
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "workspace_api" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arns.workspace_api
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "connect_api" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arns.connect_api
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "restart_jupyter" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arns.restart_jupyter
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "dicom_api" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_invoke_arns.dicom_api
  payload_format_version = "2.0"
}

# ─────────────────────────────────────────
# Routes
# ─────────────────────────────────────────
resource "aws_apigatewayv2_route" "admin_users" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /admin/users"
  target             = "integrations/${aws_apigatewayv2_integration.admin_api.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "admin_add_group" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /admin/users/{username}/groups/{group}"
  target             = "integrations/${aws_apigatewayv2_integration.admin_api.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "admin_remove_group" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "DELETE /admin/users/{username}/groups/{group}"
  target             = "integrations/${aws_apigatewayv2_integration.admin_api.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "admin_terminate_instance" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /admin/instances/{instance_id}/terminate"
  target             = "integrations/${aws_apigatewayv2_integration.admin_api.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "logs_groups" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /logs"
  target             = "integrations/${aws_apigatewayv2_integration.logs_api.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "logs_events" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /logs/events"
  target             = "integrations/${aws_apigatewayv2_integration.logs_api.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "start_compute" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /compute/start"
  target             = "integrations/${aws_apigatewayv2_integration.start_compute.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "stop_compute" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /compute/stop"
  target             = "integrations/${aws_apigatewayv2_integration.stop_compute.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "status_compute" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /compute/status"
  target             = "integrations/${aws_apigatewayv2_integration.status_compute.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "workspace_get" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /workspace/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.workspace_api.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "workspace_put" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "PUT /workspace/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.workspace_api.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "workspace_delete" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "DELETE /workspace/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.workspace_api.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "workspace_root" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /workspace"
  target             = "integrations/${aws_apigatewayv2_integration.workspace_api.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "connect_credentials" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /connect/credentials"
  target             = "integrations/${aws_apigatewayv2_integration.connect_api.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "restart_jupyter" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "POST /compute/restart-jupyter"
  target             = "integrations/${aws_apigatewayv2_integration.restart_jupyter.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "dcv_token" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /connect/dcv-token"
  target             = "integrations/${aws_apigatewayv2_integration.restart_jupyter.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "dicom_studies" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "GET /dicom/studies"
  target             = "integrations/${aws_apigatewayv2_integration.dicom_api.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

# ─────────────────────────────────────────
# Lambda Permissions
# ─────────────────────────────────────────
resource "aws_lambda_permission" "admin_api" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_names.admin_api
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*/admin*"
}

resource "aws_lambda_permission" "logs_api" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_names.logs_api
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*/logs*"
}

resource "aws_lambda_permission" "start_compute" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_names.start_compute
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*/compute/start"
}

resource "aws_lambda_permission" "stop_compute" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_names.stop_compute
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*/compute/stop"
}

resource "aws_lambda_permission" "status_compute" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_names.status_compute
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*/compute/status"
}

resource "aws_lambda_permission" "workspace_api" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_names.workspace_api
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*/workspace*"
}

resource "aws_lambda_permission" "connect_api" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_names.connect_api
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*/connect*"
}

resource "aws_lambda_permission" "restart_jupyter" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_names.restart_jupyter
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*/*"
}

resource "aws_lambda_permission" "dicom_api" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_names.dicom_api
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*/dicom*"
}
