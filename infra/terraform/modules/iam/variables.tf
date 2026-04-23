variable "project" { type = string }
variable "env" { type = string }
variable "workspace_bucket_arn" { type = string }
variable "notification_topic_arn" {
  type    = string
  default = ""
}
variable "cognito_user_pool_arn" {
  type    = string
  default = "*"
}
