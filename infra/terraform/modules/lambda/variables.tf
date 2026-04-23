variable "project" { type = string }
variable "env" { type = string }
variable "region" { type = string }

variable "role_arns" {
  type = object({
    start_compute   = string
    stop_compute    = string
    status_compute  = string
    workspace_api   = string
    notify_status   = string
    admin_api       = string
    logs_api        = string
    cleanup_compute = string
    connect_api     = string
  })
}

variable "launch_template_id" {
  type        = string
  description = "EC2 起動テンプレート ID（start_compute Lambda が使用）"
  default     = ""
}

variable "private_subnet_ids"    { type = list(string) }
variable "lambda_sg_id"          { type = string }
variable "workspace_bucket_name" { type = string }
variable "notification_topic_arn" {
  type    = string
  default = ""
}
variable "cognito_user_pool_id" {
  type    = string
  default = ""
}

variable "ssm_connect_role_arn" {
  type        = string
  description = "connect_api Lambda が assume_role するロールの ARN"
  default     = ""
}
