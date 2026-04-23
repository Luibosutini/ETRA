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

# ─────────────────────────────────────────
# デスクトップ環境（XFCE）
# MATLAB App Designer の GUI に必要
# ─────────────────────────────────────────
dnf install -y \
  xorg-x11-server-Xorg \
  xorg-x11-xinit \
  xorg-x11-utils \
  dbus-x11 \
  mesa-dri-drivers \
  mesa-libGL \
  libXrender \
  libXtst \
  libXi \
  libXext \
  libX11 \
  gtk3 \
  gtk2 \
  xterm

# XFCE（Amazon Linux 2023 で利用可能な場合）
dnf groupinstall -y "Xfce" 2>/dev/null || \
  dnf install -y \
    xfce4-session \
    xfwm4 \
    xfce4-panel \
    xfdesktop \
    xfce4-terminal \
    Thunar 2>/dev/null || true

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
# Amazon DCV Server
# MATLAB App Designer GUI セッションを提供する
# ─────────────────────────────────────────

# GPG キーをインポート
rpm --import https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY

# NICE DCV パッケージをダウンロード（RHEL9/AL2023 向け el9 パッケージ）
# バージョンは https://www.nice-dcv.com/ で最新を確認してください
DCV_VERSION="2024.0-19030"
DCV_OS="el9"
DCV_ARCH="x86_64"
DCV_PKG="nice-dcv-$${DCV_VERSION}-$${DCV_OS}-$${DCV_ARCH}"

curl -fsSL -o "/tmp/$${DCV_PKG}.tgz" \
  "https://d1uj6qtbmh3dt5.cloudfront.net/$${DCV_PKG}.tgz"
tar -xzf "/tmp/$${DCV_PKG}.tgz" -C /tmp/
cd "/tmp/$${DCV_PKG}"

dnf install -y \
  nice-dcv-server-*.$${DCV_OS}.$${DCV_ARCH}.rpm \
  nice-xdcv-*.$${DCV_OS}.$${DCV_ARCH}.rpm \
  nice-dcv-web-viewer-*.rpm

cd / && rm -rf "/tmp/$${DCV_PKG}" "/tmp/$${DCV_PKG}.tgz"

# DCV 設定
# - バーチャルセッションを自動作成（ec2-user 所有）
# - ポートは 8443 のデフォルト（SSM ポートフォワード経由でのみアクセス）
# - 認証は OS 認証（system）。SSM がすでに AWS IAM で利用者を確認済み
cat >> /etc/dcv/dcv.conf <<'EOF'

[session-management]
create-session = true

[session-management/automatic-console-session]
owner = "ec2-user"
storage-root = "/home/ec2-user/workspace"

[display]
target-fps = 15

[connectivity]
# web-listening-port = 8443 はデフォルト値
idle-timeout = 240
EOF

# DCV サービスを有効化
systemctl enable --now dcvserver

# セッション接続トークン生成スクリプト
# 管理者が SSM セッション内で実行し、ワンタイムURL を利用者に伝える
cat > /usr/local/bin/dcv-token <<'EOF'
#!/bin/bash
# DCV 接続用トークンを生成してURLを表示する
# 使用方法: sudo dcv-token
set -euo pipefail
TOKEN=$(dcv generate-session-token main 2>/dev/null | grep -oP '(?<=authToken=)[^&]+' || \
        dcv generate-session-token main 2>&1 | tail -1)
echo ""
echo "=== DCV 接続 URL ==="
echo "ブラウザで以下にアクセス（SSM ポートフォワード済みの場合のみ有効）:"
echo "https://localhost:8443/?authToken=$${TOKEN}#main"
echo ""
echo "トークン有効期限: 30 秒"
echo "===================="
EOF
chmod +x /usr/local/bin/dcv-token

echo "=== ETRA analysis node bootstrap complete: $(date) ==="
