variable "project" {
  type    = string
  default = "etra"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "ec2_instance_type" {
  description = "解析ノードのインスタンスタイプ（MATLAB ライセンス確定後に更新）"
  type        = string
  default     = "t3.xlarge"
}

variable "ami_id" {
  description = "Packer でビルドした ETRA カスタム AMI ID（scripts/deploy/build_ami.sh で作成）"
  type        = string
}

variable "allowed_email_domains" {
  description = "Cognito への登録を許可するメールドメイン（例: 大学のドメイン）"
  type        = list(string)
}

variable "allowed_emails" {
  description = "登録を許可するメールアドレスのホワイトリスト（大学全体ドメインを使う場合に研究室メンバーを限定する）"
  type        = list(string)
  default     = []
}

variable "cognito_callback_urls" {
  type    = list(string)
  default = ["https://localhost:3000/callback"]
}

variable "cognito_logout_urls" {
  type    = list(string)
  default = ["https://localhost:3000/logout"]
}

variable "alert_emails" {
  description = "CloudWatch アラーム・Budgets の通知先メールアドレスリスト"
  type        = list(string)
  default     = []
}

variable "monthly_budget_usd" {
  description = "月間コスト上限（USD）"
  type        = string
  default     = "100"
}
