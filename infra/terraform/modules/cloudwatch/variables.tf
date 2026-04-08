variable "project" { type = string }
variable "env" { type = string }
variable "alert_emails" {
  description = "CloudWatch アラームおよび Budgets の通知先メールアドレスリスト"
  type        = list(string)
  default     = []
}
variable "lambda_function_names" {
  type    = map(string)
  default = {}
}
variable "monthly_budget_usd" {
  type    = string
  default = "100"
}
