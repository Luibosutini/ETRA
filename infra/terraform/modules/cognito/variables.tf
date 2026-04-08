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
  description = "登録を許可するメールドメインのリスト（例: [\"lab.university.ac.jp\"]）"
  type        = list(string)
}
