locals {
  name_prefix = "${var.project}-${var.env}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─────────────────────────────────────────
# Pre-signup Lambda トリガー
# ─────────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pre_signup" {
  name               = "${local.name_prefix}-cognito-pre-signup"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "pre_signup_logs" {
  role       = aws_iam_role.pre_signup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "pre_signup" {
  function_name    = "${local.name_prefix}-cognito-pre-signup"
  role             = aws_iam_role.pre_signup.arn
  handler          = "cognito_pre_signup.handler"
  runtime          = "python3.11"
  timeout          = 5
  filename         = "${path.module}/pre_signup_placeholder.zip"
  source_code_hash = filebase64sha256("${path.module}/pre_signup_placeholder.zip")

  environment {
    variables = {
      ALLOWED_EMAIL_DOMAINS = join(",", var.allowed_email_domains)
      ALLOWED_EMAILS        = join(",", var.allowed_emails)
    }
  }
}

resource "aws_cloudwatch_log_group" "pre_signup" {
  name              = "/aws/lambda/${aws_lambda_function.pre_signup.function_name}"
  retention_in_days = 30
}

# Cognito が Lambda を呼び出せるようにする
resource "aws_lambda_permission" "cognito_pre_signup" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pre_signup.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.this.arn
}

# ─────────────────────────────────────────
# Post-confirmation Lambda トリガー
# サインアップ完了後に user グループへ自動追加する
# ─────────────────────────────────────────
resource "aws_iam_role" "post_confirmation" {
  name               = "${local.name_prefix}-cognito-post-confirmation"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "post_confirmation_logs" {
  role       = aws_iam_role.post_confirmation.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "post_confirmation_cognito" {
  name = "${local.name_prefix}-post-confirmation-cognito"
  role = aws_iam_role.post_confirmation.id
  # user pool ARN を直接参照すると循環依存になるため data source で構築する
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "cognito-idp:AdminAddUserToGroup"
      Resource = "arn:aws:cognito-idp:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:userpool/*"
    }]
  })
}

resource "aws_lambda_function" "post_confirmation" {
  function_name    = "${local.name_prefix}-cognito-post-confirmation"
  role             = aws_iam_role.post_confirmation.arn
  handler          = "cognito_post_confirmation.handler"
  runtime          = "python3.11"
  timeout          = 5
  filename         = "${path.module}/pre_signup_placeholder.zip"
  source_code_hash = filebase64sha256("${path.module}/pre_signup_placeholder.zip")
  # USER_POOL_ID は Cognito トリガーの event.userPoolId に含まれるため不要
}

resource "aws_cloudwatch_log_group" "post_confirmation" {
  name              = "/aws/lambda/${aws_lambda_function.post_confirmation.function_name}"
  retention_in_days = 30
}

resource "aws_lambda_permission" "cognito_post_confirmation" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_confirmation.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.this.arn
}

# ─────────────────────────────────────────
# Cognito User Pool
# ─────────────────────────────────────────
resource "aws_cognito_user_pool" "this" {
  name = "${local.name_prefix}-user-pool"

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  auto_verified_attributes = ["email"]

  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = true
    string_attribute_constraints {
      min_length = 5
      max_length = 256
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  lambda_config {
    pre_sign_up       = aws_lambda_function.pre_signup.arn
    post_confirmation = aws_lambda_function.post_confirmation.arn
  }

  tags = { Name = "${local.name_prefix}-user-pool" }
}


# ─────────────────────────────────────────
# User Pool Client
# ─────────────────────────────────────────
resource "aws_cognito_user_pool_client" "this" {
  name         = "${local.name_prefix}-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls
  supported_identity_providers         = ["COGNITO"]

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30
}

# ─────────────────────────────────────────
# User Pool Domain
# ─────────────────────────────────────────
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${local.name_prefix}-auth"
  user_pool_id = aws_cognito_user_pool.this.id
}

# ─────────────────────────────────────────
# グループ（管理者 / 一般利用者）
# ─────────────────────────────────────────
resource "aws_cognito_user_group" "admin" {
  name         = "admin"
  user_pool_id = aws_cognito_user_pool.this.id
  description  = "管理者グループ"
  precedence   = 1
}

resource "aws_cognito_user_group" "user" {
  name         = "user"
  user_pool_id = aws_cognito_user_pool.this.id
  description  = "一般利用者グループ"
  precedence   = 10
}
