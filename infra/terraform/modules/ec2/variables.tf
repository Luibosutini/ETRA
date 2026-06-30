variable "project" { type = string }
variable "env" { type = string }
variable "region" { type = string }
variable "instance_type" {
  type    = string
  default = "m7i.2xlarge"
}
variable "ami_id" {
  type        = string
  description = "Packer でビルドした ETRA カスタム AMI ID（build_ami.sh で作成）"
  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id は 'ami-' で始まる有効な AMI ID である必要があります。build_ami.sh を実行して取得してください。"
  }
}
variable "instance_profile_name" { type = string }
variable "security_group_id" { type = string }
variable "subnet_id" { type = string }
variable "workspace_bucket_name" { type = string }
variable "root_volume_size_gb" {
  type    = number
  default = 100
}
