variable "state_bucket_name" {
  description = "Terraform state を格納する S3 バケット名"
  type        = string
}

variable "lock_table_name" {
  description = "Terraform state ロック用 DynamoDB テーブル名"
  type        = string
  default     = "etra-tf-lock"
}