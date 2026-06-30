variable "project" { type = string }
variable "env" { type = string }

variable "cognito_user_pool_id" { type = string }
variable "cognito_client_id" { type = string }
variable "cognito_auth_domain" { type = string }

variable "lambda_invoke_arns" {
  type = object({
    start_compute   = string
    stop_compute    = string
    status_compute  = string
    workspace_api   = string
    admin_api       = string
    logs_api        = string
    connect_api     = string
    restart_jupyter = string
    dicom_api       = string
  })
}

variable "lambda_function_names" {
  type = object({
    start_compute   = string
    stop_compute    = string
    status_compute  = string
    workspace_api   = string
    admin_api       = string
    logs_api        = string
    connect_api     = string
    restart_jupyter = string
    dicom_api       = string
  })
}

variable "allowed_origins" {
  type        = list(string)
  description = "CORS 許可オリジン（CloudFront ドメインと開発用 localhost を含む）"
  default     = ["http://localhost:5173"]
}
