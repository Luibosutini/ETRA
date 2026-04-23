variable "project" { type = string }
variable "env" { type = string }
variable "region" { type = string }
variable "instance_type" {
  type    = string
  default = "m7i.2xlarge"
}
variable "ami_id" {
  type    = string
  default = ""  # 空の場合は最新 Amazon Linux 2023 を使用
}
variable "instance_profile_name" { type = string }
variable "security_group_id" { type = string }
variable "subnet_id" { type = string }
variable "workspace_bucket_name" { type = string }
variable "root_volume_size_gb" {
  type    = number
  default = 100
}
