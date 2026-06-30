#!/bin/bash
exec > >(tee /var/log/userdata.log | logger -t userdata) 2>&1
echo "=== ETRA analysis node userdata start: $(date) ==="

# ─────────────────────────────────────────
# インスタンス固有の設定を書き込む
# ─────────────────────────────────────────
mkdir -p /etc/etra
cat > /etc/etra/config.env <<EOF
WORKSPACE_BUCKET=${workspace_bucket}
REGION=${region}
EOF
chmod 644 /etc/etra/config.env

# ─────────────────────────────────────────
# SSM Agent の状態を診断ログとして S3 に送信
# ─────────────────────────────────────────
INSTANCE_ID=$(TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60") && curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id || echo "unknown")
{
  echo "=== SSM Agent status: $(date) ==="
  systemctl status amazon-ssm-agent --no-pager || true
  echo "=== SSM Agent log (last 30 lines) ==="
  tail -30 /var/log/amazon/ssm/amazon-ssm-agent.log 2>/dev/null || echo "log not found"
  echo "=== IAM role check ==="
  curl -sf -H "X-aws-ec2-metadata-token: $(curl -sf -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" \
    http://169.254.169.254/latest/meta-data/iam/info 2>/dev/null || echo "IMDS IAM info failed"
} > /tmp/ssm-diag.txt 2>&1
aws s3 cp /tmp/ssm-diag.txt "s3://${workspace_bucket}/debug/ssm-diag-$${INSTANCE_ID}.txt" --region ${region} || true

# ─────────────────────────────────────────
# DCV virtual session 用デスクトップ起動設定の保証
# 旧 AMI 対策: ~/.xsession が無いと virtual session に WM が起動せず
# ログイン後に画面が遷移しないため、無ければ生成してセッションを作り直す
# ─────────────────────────────────────────
NEED_DCV_RECREATE=0
if [ ! -f /home/ec2-user/.xsession ]; then
  cat > /home/ec2-user/.xsession <<'XS'
#!/bin/bash
export XDG_SESSION_TYPE=x11
if command -v startxfce4 >/dev/null 2>&1; then
  exec startxfce4
else
  exec xfce4-session
fi
XS
  chown ec2-user:ec2-user /home/ec2-user/.xsession
  chmod 755 /home/ec2-user/.xsession
  NEED_DCV_RECREATE=1
fi

# ─────────────────────────────────────────
# DCV 設定パッチ（SSM TCP トンネル経由のため QUIC を無効化）
# ─────────────────────────────────────────
if ! grep -q 'enable-quic-frontend' /etc/dcv/dcv.conf 2>/dev/null; then
  sed -i '/^\[connectivity\]/a enable-quic-frontend=false' /etc/dcv/dcv.conf || \
    echo -e '\n[connectivity]\nenable-quic-frontend=false' >> /etc/dcv/dcv.conf
fi

# ─────────────────────────────────────────
# サービスを明示的に起動
# ─────────────────────────────────────────
systemctl daemon-reload
systemctl start dcvserver || true

# .xsession を新規生成した場合は既存 session を作り直す
if [ "$${NEED_DCV_RECREATE}" = "1" ]; then
  dcv close-session etra 2>/dev/null || true
fi

# DCV 仮想セッション etra の存在を毎起動で保証（無ければ作成、dcvserver 起動待ちでリトライ）
mkdir -p /home/ec2-user/workspace
chown ec2-user:ec2-user /home/ec2-user/workspace
for i in $(seq 1 20); do
  if dcv list-sessions 2>/dev/null | grep -q etra; then
    echo "DCV session etra already present"
    break
  fi
  if dcv create-session --type virtual --owner ec2-user --user ec2-user \
       --storage-root /home/ec2-user/workspace etra 2>/dev/null; then
    echo "DCV session etra created"
    break
  fi
  echo "waiting for dcvserver... ($i/20)"
  sleep 3
done
dcv list-sessions || true

systemctl restart jupyterlab || true

echo "=== ETRA analysis node userdata complete: $(date) ==="
