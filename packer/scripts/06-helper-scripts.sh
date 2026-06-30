#!/bin/bash
set -euo pipefail
echo "=== 06-helper-scripts start: $(date) ==="

# S3 ワークスペース同期スクリプト
# /etc/etra/config.env（userdata で書き込む）から設定を読む
cat > /usr/local/bin/ws-sync-down <<'EOF'
#!/bin/bash
# S3 personal/ 領域をローカルへ同期（起動時）
CONFIG=/etc/etra/config.env
if [ ! -f "$CONFIG" ]; then
  echo "ws-sync-down: $CONFIG が見つかりません。スキップします。"
  exit 0
fi
source "$CONFIG"
if [ -z "${WORKSPACE_BUCKET:-}" ] || [ -z "${REGION:-}" ]; then
  echo "ws-sync-down: WORKSPACE_BUCKET または REGION が未設定です。スキップします。"
  exit 0
fi
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
OWNER=$(aws ec2 describe-tags --region "${REGION}" \
  --filters "Name=resource-id,Values=${INSTANCE_ID}" "Name=key,Values=Owner" \
  --query "Tags[0].Value" --output text 2>/dev/null || echo "")
if [ -z "$OWNER" ] || [ "$OWNER" = "None" ]; then
  echo "ws-sync-down: Owner タグが見つかりません。スキップします。"
  exit 0
fi
mkdir -p /home/ec2-user/workspace/personal
aws s3 sync "s3://${WORKSPACE_BUCKET}/personal/${OWNER}/" \
  /home/ec2-user/workspace/personal/ \
  --region "${REGION}"
echo "Workspace synced from S3 (owner: ${OWNER}): $(date)"
EOF

cat > /usr/local/bin/ws-sync-up <<'EOF'
#!/bin/bash
# ローカルを S3 personal/ 領域へ同期（手動 or 停止前）
CONFIG=/etc/etra/config.env
if [ ! -f "$CONFIG" ]; then
  echo "ws-sync-up: $CONFIG が見つかりません。スキップします。"
  exit 0
fi
source "$CONFIG"
if [ -z "${WORKSPACE_BUCKET:-}" ] || [ -z "${REGION:-}" ]; then
  echo "ws-sync-up: WORKSPACE_BUCKET または REGION が未設定です。スキップします。"
  exit 0
fi
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
OWNER=$(aws ec2 describe-tags --region "${REGION}" \
  --filters "Name=resource-id,Values=${INSTANCE_ID}" "Name=key,Values=Owner" \
  --query "Tags[0].Value" --output text 2>/dev/null || echo "")
if [ -z "$OWNER" ] || [ "$OWNER" = "None" ]; then
  echo "ws-sync-up: Owner タグが見つかりません。スキップします。"
  exit 0
fi
aws s3 sync /home/ec2-user/workspace/personal/ \
  "s3://${WORKSPACE_BUCKET}/personal/${OWNER}/" \
  --region "${REGION}" \
  --exclude "*.tmp"
echo "Workspace synced to S3 (owner: ${OWNER}): $(date)"
EOF

# DCV 接続トークン生成スクリプト
cat > /usr/local/bin/dcv-token <<'EOF'
#!/bin/bash
# DCV 接続用トークンを生成してURLを表示する
# 使用方法: sudo dcv-token
set -euo pipefail
SESSION=$(dcv list-sessions 2>/dev/null | grep -oP "Session: '\K[^']+" | head -1)
SESSION=${SESSION:-console}
TOKEN=$(dcv generate-session-token "${SESSION}" 2>/dev/null | grep -oP '(?<=authToken=)[^&]+' || \
        dcv generate-session-token "${SESSION}" 2>&1 | tail -1)
echo ""
echo "=== DCV 接続 URL ==="
echo "ブラウザで以下にアクセス（SSM ポートフォワード済みの場合のみ有効）:"
echo "https://localhost:8443/?authToken=${TOKEN}#${SESSION}"
echo ""
echo "トークン有効期限: 30 秒"
echo "===================="
EOF

chmod +x /usr/local/bin/ws-sync-down /usr/local/bin/ws-sync-up /usr/local/bin/dcv-token

echo "=== 06-helper-scripts done: $(date) ==="
