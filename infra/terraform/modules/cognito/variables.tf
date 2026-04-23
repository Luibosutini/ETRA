variable "project" { type = string }
variable "env" { type = string }
variable "callback_urls" {
  type    = list(string)
  default = ["https://localhost:3000/callback"]
}
variable "logout_urls" {
  type    = list(string)
  default = ["https://localhost:3000/logout"]
}
variable "allowed_email_domains" {
  description = "登録を許可するメールドメインのリスト（例: [\"university.ac.jp\"]）"
  type        = list(string)
}

variable "allowed_emails" {
  description = "登録を許可するメールアドレスのホワイトリスト。設定した場合はドメイン一致に加えてアドレスも照合する（例: [\"alice@university.ac.jp\"]）"
  type        = list(string)
  default     = []
}
