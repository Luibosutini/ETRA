variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "allowed_origins" {
  type        = list(string)
  description = "S3 CORS で許可するオリジン一覧（CloudFront ドメインと localhost）"
}
