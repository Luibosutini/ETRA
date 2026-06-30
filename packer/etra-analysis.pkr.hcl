packer {
  required_version = ">= 1.10"
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

data "amazon-ami" "al2023" {
  filters = {
    name                = "al2023-ami-*-x86_64"
    virtualization-type = "hvm"
    root-device-type    = "ebs"
  }
  owners      = ["amazon"]
  most_recent = true
}

source "amazon-ebs" "etra_analysis" {
  region        = var.region
  source_ami    = data.amazon-ami.al2023.id
  instance_type = var.builder_instance_type
  ssh_username  = "ec2-user"

  # ビルド用サブネット（インターネットアクセスが必要なためパブリック）
  subnet_id                   = var.builder_subnet_id
  associate_public_ip_address = true

  ami_name        = "${var.ami_name_prefix}-${formatdate("YYYYMMDDHHmmss", timestamp())}"
  ami_description = "ETRA analysis node: JupyterLab + DCV + Python (baked)"

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = false # 起動テンプレートで EBS 暗号化するため AMI 自体は不要
    delete_on_termination = true
  }

  tags = {
    Name        = var.ami_name_prefix
    Project     = var.project
    Environment = var.env
    BuildDate   = formatdate("YYYY-MM-DD", timestamp())
    ManagedBy   = "Packer"
  }

  snapshot_tags = {
    Project   = var.project
    ManagedBy = "Packer"
  }
}

build {
  name    = "etra-analysis"
  sources = ["source.amazon-ebs.etra_analysis"]

  # 1. 基本パッケージ（Python 3.11、開発ツール）
  provisioner "shell" {
    script          = "${path.root}/scripts/01-base-packages.sh"
    execute_command = "sudo bash '{{.Path}}'"
  }

  # 2. デスクトップ環境（XFCE — MATLAB GUI に必要）
  provisioner "shell" {
    script          = "${path.root}/scripts/02-desktop-xfce.sh"
    execute_command = "sudo bash '{{.Path}}'"
  }

  # 3. Python 解析ライブラリ + JupyterLab
  provisioner "shell" {
    script          = "${path.root}/scripts/03-python-jupyter.sh"
    execute_command = "sudo bash '{{.Path}}'"
  }

  # 4. Amazon DCV Server
  provisioner "shell" {
    script          = "${path.root}/scripts/04-dcv-server.sh"
    execute_command = "sudo bash '{{.Path}}'"
  }

  # 5. systemd サービスファイル（jupyterlab、ws-sync-on-shutdown）
  provisioner "shell" {
    script          = "${path.root}/scripts/05-systemd-services.sh"
    execute_command = "sudo bash '{{.Path}}'"
  }

  # 6. ヘルパースクリプト（ws-sync-down/up、dcv-token）
  provisioner "shell" {
    script          = "${path.root}/scripts/06-helper-scripts.sh"
    execute_command = "sudo bash '{{.Path}}'"
  }

  # 7. MATLAB installation via mpm
  provisioner "shell" {
    script          = "${path.root}/scripts/07-matlab.sh"
    execute_command = "sudo -E bash '{{.Path}}'"
    environment_vars = [
      "MATLAB_RELEASE=${var.matlab_release}",
      "MATLAB_PRODUCTS=${var.matlab_products}",
    ]
  }

  # 8. AMI 焼き付け前クリーンアップ
  #    ビルダーインスタンスの SSM 登録情報を消す。
  #    残したまま AMI を作ると新規インスタンスが古い Instance ID で再登録しようとして
  #    SSM に接続できなくなる。
  provisioner "shell" {
    inline = [
      "sudo systemctl stop amazon-ssm-agent || true",
      "sudo rm -rf /var/lib/amazon/ssm/ipc/ || true",
      "sudo rm -f  /var/lib/amazon/ssm/registration || true",
      "sudo systemctl enable amazon-ssm-agent || true",
      "echo 'SSM Agent cleanup done'",
    ]
  }
}
