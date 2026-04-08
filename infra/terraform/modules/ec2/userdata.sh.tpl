#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────
# 基本パッケージ
# ─────────────────────────────────────────
dnf update -y
dnf install -y python3.11 python3.11-pip git awscli

# ─────────────────────────────────────────
# Python 解析環境
# ─────────────────────────────────────────
python3.11 -m pip install --upgrade pip
python3.11 -m pip install \
  jupyterlab==4.* \
  numpy==2.* \
  scipy \
  pandas==2.* \
  matplotlib \
  boto3

# JupyterLab をシステムサービスとして起動
cat > /etc/systemd/system/jupyterlab.service << 'EOF'
[Unit]
Description=JupyterLab
After=network.target

[Service]
Type=simple
User=ec2-user
ExecStart=/usr/local/bin/jupyter lab \
  --no-browser \
  --ip=127.0.0.1 \
  --port=8888 \
  --NotebookApp.token='' \
  --NotebookApp.password='' \
  --notebook-dir=/home/ec2-user/workspace
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable jupyterlab

# ─────────────────────────────────────────
# ワークスペースディレクトリ作成
# ─────────────────────────────────────────
sudo -u ec2-user mkdir -p /home/ec2-user/workspace/{personal,shared,results}

# ─────────────────────────────────────────
# Amazon DCV インストール（GUI 利用時）
# ─────────────────────────────────────────
# NOTE: MATLAB GUI を使用する場合は以下を有効化し、
#       DCV ライセンスサーバーの設定を行うこと。
# rpm --import https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY
# dnf install -y nice-dcv-server nice-dcv-web-viewer

# ─────────────────────────────────────────
# SSM Agent（Amazon Linux 2023 には標準搭載）
# ─────────────────────────────────────────
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

echo "Userdata completed: $(date)" >> /var/log/userdata.log
