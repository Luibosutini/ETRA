variable "project" { type = string }
variable "env" { type = string }

variable "frontend_bucket_name" {
  description = "OHIF Viewer の静的ファイルを格納する S3 バケット名"
  type        = string
}

variable "frontend_bucket_arn" {
  description = "フロントエンド S3 バケットの ARN"
  type        = string
}

variable "frontend_bucket_regional_domain" {
  description = "フロントエンド S3 バケットのリージョナルドメイン名"
  type        = string
}

variable "acm_certificate_arn" {
  description = "カスタムドメイン用 ACM 証明書 ARN（us-east-1 で発行済みのもの）"
  type        = string
  default     = ""
}
