variable "project" { type = string }
variable "env" { type = string }
variable "region" { type = string }

variable "role_arns" {
  type = object({
    start_compute  = string
    stop_compute   = string
    status_compute = string
    workspace_api  = string
    notify_status  = string
  })
}

variable "private_subnet_ids"    { type = list(string) }
variable "lambda_sg_id"          { type = string }
variable "workspace_bucket_name" { type = string }
variable "notification_topic_arn" {
  type    = string
  default = ""
}
