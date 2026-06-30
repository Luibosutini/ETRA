variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "etra"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "builder_subnet_id" {
  type        = string
  description = "パブリックサブネット ID（インターネットアクセスが必要）"
}

variable "builder_instance_type" {
  type        = string
  default     = "t3.large"
  description = "AMI ビルド用の一時インスタンスタイプ"
}

variable "ami_name_prefix" {
  type    = string
  default = "etra-analysis"
}

variable "root_volume_size_gb" {
  type        = number
  default     = 150
  description = "AMI のルートボリュームサイズ（起動テンプレートで拡張する）"
}

variable "matlab_release" {
  type    = string
  default = "R2024b"
}

variable "matlab_products" {
  type    = string
  default = "MATLAB Simulink Image_Processing_Toolbox Signal_Processing_Toolbox Statistics_and_Machine_Learning_Toolbox Optimization_Toolbox Parallel_Computing_Toolbox Curve_Fitting_Toolbox Control_System_Toolbox"
}
