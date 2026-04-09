#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/userdata.log | logger -t userdata) 2>&1

echo "=== ETRA analysis node bootstrap start ==="
REGION="${region}"
WORKSPACE_BUCKET="${workspace_bucket}"

# ─────────────────────────────────────────
# システム更新・基本ツール
# ─────────────────────────────────────────
dnf update -y
dnf install -y \
  git \
  htop \
  jq \
  unzip \
  tmux \
  gcc \
  gcc-c++ \
  make \
  openssl-devel \
  bzip2-devel \
  libffi-devel \
  zlib-devel \
  python3.11 \
  python3.11-pip \
  python3.11-devel

alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1
alternatives --install /usr/bin/pip3 pip3 /usr/bin/pip3.11 1

# ─────────────────────────────────────────
# 解析ライブラリ（CLAUDE.md 技術スタック準拠）
# ─────────────────────────────────────────
pip3 install --upgrade pip
pip3 install \
  "jupyterlab>=4.0,<5.0" \
  "numpy>=2.0,<3.0" \
  "scipy>=1.13,<2.0" \
  "pandas>=2.0,<3.0" \
  "matplotlib>=3.8,<4.0" \
  "boto3>=1.0,<2.0" \
  "pydicom" \
  "Pillow" \
  "scikit-image" \
  "ipywidgets" \
  "jupyterlab-widgets"

# ─────────────────────────────────────────
# JupyterLab 設定
# SSM ポートフォワーディング経由でのみアクセスするため
# バインドは 127.0.0.1 のみ・トークンなし
# ─────────────────────────────────────────
mkdir -p /home/ec2-user/.jupyter
cat > /home/ec2-user/.jupyter/jupyter_lab_config.py <<'EOF'
c.ServerApp.ip = '127.0.0.1'
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.token = ''
c.ServerApp.password = ''
c.ServerApp.root_dir = '/home/ec2-user/workspace'
c.ServerApp.allow_remote_access = False
EOF

chown -R ec2-user:ec2-user /home/ec2-user/.jupyter

# ─────────────────────────────────────────
# ワークスペースディレクトリ作成
# ─────────────────────────────────────────
sudo -u ec2-user mkdir -p /home/ec2-user/workspace/{personal,shared,results}

# ─────────────────────────────────────────
# S3 ワークスペース同期スクリプト
# ─────────────────────────────────────────
cat > /usr/local/bin/ws-sync-down <<EOF
#!/bin/bash
# S3 personal/ 領域をローカルへ同期（起動時）
INSTANCE_ID=\$(TOKEN=\$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60") && \
  curl -s -H "X-aws-ec2-metadata-token: \$TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
aws s3 sync "s3://$WORKSPACE_BUCKET/personal/\$INSTANCE_ID/" \
  /home/ec2-user/workspace/personal/ \
  --region $REGION
echo "Workspace synced from S3: \$(date)"
EOF

cat > /usr/local/bin/ws-sync-up <<EOF
#!/bin/bash
# ローカルを S3 personal/ 領域へ同期（手動 or 停止前）
INSTANCE_ID=\$(TOKEN=\$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60") && \
  curl -s -H "X-aws-ec2-metadata-token: \$TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
aws s3 sync /home/ec2-user/workspace/personal/ \
  "s3://$WORKSPACE_BUCKET/personal/\$INSTANCE_ID/" \
  --region $REGION \
  --exclude "*.tmp"
echo "Workspace synced to S3: \$(date)"
EOF

chmod +x /usr/local/bin/ws-sync-down /usr/local/bin/ws-sync-up

# ─────────────────────────────────────────
# JupyterLab systemd サービス
# ─────────────────────────────────────────
cat > /etc/systemd/system/jupyterlab.service <<'EOF'
[Unit]
Description=JupyterLab
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/workspace
ExecStartPre=/usr/local/bin/ws-sync-down
ExecStart=/usr/bin/python3 -m jupyterlab
Restart=on-failure
RestartSec=10
Environment=PATH=/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable jupyterlab
systemctl start jupyterlab

# ─────────────────────────────────────────
# 停止前に S3 同期するシャットダウンフック
# ─────────────────────────────────────────
cat > /etc/systemd/system/ws-sync-on-shutdown.service <<'EOF'
[Unit]
Description=Sync workspace to S3 before shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ws-sync-up
TimeoutStartSec=120
RemainAfterExit=yes

[Install]
WantedBy=halt.target reboot.target shutdown.target
EOF

systemctl daemon-reload
systemctl enable ws-sync-on-shutdown

# ─────────────────────────────────────────
# SSM Agent（Amazon Linux 2023 には標準搭載）
# ─────────────────────────────────────────
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# ─────────────────────────────────────────
# Amazon DCV セットアップ予約
# MATLAB GUI が必要になった時点で有効化する
# ─────────────────────────────────────────
# TODO: MATLAB ライセンス・インスタンスタイプ確定後に以下を有効化
# rpm --import https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY
# dnf install -y nice-dcv-server nice-dcv-web-viewer
# systemctl enable --now dcvserver

echo "=== ETRA analysis node bootstrap complete: $(date) ==="
