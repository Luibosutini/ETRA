variable "project" {
  description = "プロジェクト名"
  type        = string
}

variable "env" {
  description = "環境名（dev / stg / prod）"
  type        = string
}

variable "region" {
  description = "AWS リージョン"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR ブロック"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "使用する AZ のリスト"
  type        = list(string)
}

variable "private_subnets" {
  description = "プライベートサブネット CIDR のリスト（azs と同じ順序）"
  type        = list(string)
}

variable "public_subnets" {
  description = "パブリックサブネット CIDR のリスト（azs と同じ順序）"
  type        = list(string)
}

