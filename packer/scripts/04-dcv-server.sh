#!/bin/bash
set -euo pipefail
echo "=== 04-dcv-server start: $(date) ==="

# GPG キーをインポート
rpm --import https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY

# Amazon DCV パッケージをダウンロード（Amazon Linux 2023 向け）
# バージョン: https://www.amazondcv.com/ で確認
DCV_VERSION="2025.0-20103"
DCV_OS="amzn2023"
DCV_ARCH="x86_64"
DCV_PKG="nice-dcv-${DCV_VERSION}-${DCV_OS}-${DCV_ARCH}"

curl -fsSL -o "/tmp/${DCV_PKG}.tgz" \
  "https://d1uj6qtbmh3dt5.cloudfront.net/2025.0/Servers/${DCV_PKG}.tgz"
tar -xzf "/tmp/${DCV_PKG}.tgz" -C /tmp/
cd "/tmp/${DCV_PKG}"

dnf install -y \
  nice-dcv-server-*.amzn2023.x86_64.rpm \
  nice-xdcv-*.amzn2023.x86_64.rpm \
  nice-dcv-web-viewer-*.amzn2023.x86_64.rpm

cd / && rm -rf "/tmp/${DCV_PKG}" "/tmp/${DCV_PKG}.tgz"

# DCV 設定
# - virtual session（headless EC2 向け、DCV が仮想 X を管理）
# - create-session は使わず、systemd oneshot で起動後に作成する
# - ポートは 8443 のデフォルト（SSM ポートフォワード経由でのみアクセス）
cat >> /etc/dcv/dcv.conf <<'EOF'

[display]
target-fps = 15

[connectivity]
# web-listening-port = 8443 はデフォルト値
idle-timeout = 240
# SSM ポートフォワード経由（TCP のみ）のため QUIC(UDP) を無効化
enable-quic-frontend=false
EOF

# DCV 起動後に virtual session を作成する systemd oneshot
cat > /etc/systemd/system/dcv-session.service <<'EOF'
[Unit]
Description=Create DCV virtual session for ec2-user
After=dcvserver.service
Requires=dcvserver.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/usr/bin/mkdir -p /home/ec2-user/workspace
ExecStartPre=/usr/bin/chown ec2-user:ec2-user /home/ec2-user/workspace
ExecStart=/bin/bash -c '\
  for i in $(seq 1 20); do \
    dcv list-sessions 2>/dev/null | grep -q etra && exit 0; \
    dcv create-session --type virtual --owner ec2-user --user ec2-user \
      --storage-root /home/ec2-user/workspace etra 2>/dev/null && exit 0; \
    sleep 3; \
  done; exit 1'
ExecStop=/usr/bin/dcv close-session etra

[Install]
WantedBy=multi-user.target
EOF

systemctl enable dcvserver dcv-session.service

echo "=== 04-dcv-server done: $(date) ==="
