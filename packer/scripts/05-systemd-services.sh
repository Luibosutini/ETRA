#!/bin/bash
set -euo pipefail
echo "=== 05-systemd-services start: $(date) ==="

# JupyterLab サービス
# ExecStartPre=- の - プレフィックス:
#   S3 sync 失敗（設定ファイル未作成など）でも JupyterLab を起動する
cat > /etc/systemd/system/jupyterlab.service <<'EOF'
[Unit]
Description=JupyterLab
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/workspace
ExecStartPre=-/usr/local/bin/ws-sync-down
ExecStart=/usr/local/bin/jupyter lab
Restart=on-failure
RestartSec=10
Environment=PATH=/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
EOF

# 停止前 S3 同期サービス
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
systemctl enable jupyterlab
systemctl enable ws-sync-on-shutdown
systemctl enable amazon-ssm-agent || echo "WARN: amazon-ssm-agent enable skipped (already enabled or not found)"

echo "=== 05-systemd-services done: $(date) ==="
