#!/usr/bin/env bash
# ETRA OHIF Viewer デプロイスクリプト
#
# 使用方法:
#   cd infra/terraform/envs/dev
#   terraform apply
#   cd ../../../../
#   bash scripts/deploy/deploy_ohif.sh
#
# 前提:
#   - AWS CLI が設定済みであること
#   - Node.js 20.x / npm が利用可能であること
#   - infra/terraform/envs/dev で terraform apply 済みであること

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OHIF_DIR="$REPO_ROOT/frontend/ohif"
APP_CONFIG="$OHIF_DIR/platform/app/public/config/app-config.js"
TF_DIR="$REPO_ROOT/infra/terraform/envs/dev"

echo "==> Terraform output を取得中..."
cd "$TF_DIR"

CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain)
COGNITO_USER_POOL_ID=$(terraform output -raw cognito_user_pool_id)
COGNITO_CLIENT_ID=$(terraform output -raw cognito_client_id)
DATASTORE_ID=$(terraform output -raw healthimaging_datastore)
FRONTEND_BUCKET=$(terraform output -raw frontend_bucket_name)
REGION="us-east-1"

APP_URL="https://${CLOUDFRONT_DOMAIN}/ohif"

echo "  CLOUDFRONT_DOMAIN:  $CLOUDFRONT_DOMAIN"
echo "  DATASTORE_ID:       $DATASTORE_ID"
echo "  FRONTEND_BUCKET:    $FRONTEND_BUCKET"
echo "  APP_URL:            $APP_URL"

# ─────────────────────────────────────────
# app-config.js に実値を注入
# ─────────────────────────────────────────
echo "==> app-config.js を生成中..."
python3 - "$APP_CONFIG" \
    "$DATASTORE_ID" "$REGION" "$COGNITO_USER_POOL_ID" "$COGNITO_CLIENT_ID" "$APP_URL" \
    > "${APP_CONFIG}.generated" <<'PYEOF'
import sys

path, datastore_id, region, pool_id, client_id, app_url = sys.argv[1:7]
with open(path, 'rb') as f:
    content = f.read()

def rb(s): return s.encode('ascii')

content = content.replace(rb('${DATASTORE_ID}'),         rb(datastore_id))
content = content.replace(rb('${REGION}'),               rb(region))
content = content.replace(rb('${COGNITO_USER_POOL_ID}'), rb(pool_id))
content = content.replace(rb('${COGNITO_CLIENT_ID}'),    rb(client_id))
content = content.replace(rb('${APP_URL}'),              rb(app_url))
content = content.replace(rb("routerBasename: '/'"),     rb("routerBasename: '/ohif'"))

sys.stdout.buffer.write(content)
PYEOF

mv "${APP_CONFIG}.generated" "$APP_CONFIG"

# ─────────────────────────────────────────
# OHIF ビルド
# ─────────────────────────────────────────
echo "==> OHIF npm ビルド中（数分かかります）..."
cd "$OHIF_DIR"
npm install --legacy-peer-deps
npm run build

DIST_DIR="$OHIF_DIR/platform/app/dist"

if [ ! -d "$DIST_DIR" ]; then
    echo "ERROR: ビルド出力が見つかりません: $DIST_DIR"
    exit 1
fi

# ─────────────────────────────────────────
# S3 へアップロード
# ─────────────────────────────────────────
echo "==> S3 へアップロード中..."

# 静的アセット（コンテンツハッシュ付き）: 1年キャッシュ
aws s3 sync "$DIST_DIR/static/" "s3://${FRONTEND_BUCKET}/ohif/static/" \
    --cache-control "public, max-age=31536000, immutable" \
    --delete

# app-config.js: キャッシュ無効
aws s3 cp "$DIST_DIR/config/app-config.js" \
    "s3://${FRONTEND_BUCKET}/ohif/config/app-config.js" \
    --cache-control "no-cache, no-store, must-revalidate"

# index.html: キャッシュ無効
aws s3 cp "$DIST_DIR/index.html" \
    "s3://${FRONTEND_BUCKET}/ohif/index.html" \
    --cache-control "no-cache, no-store, must-revalidate"

# その他ファイル（favicon 等）
aws s3 sync "$DIST_DIR/" "s3://${FRONTEND_BUCKET}/ohif/" \
    --exclude "static/*" \
    --exclude "config/app-config.js" \
    --exclude "index.html" \
    --cache-control "public, max-age=3600" \
    --delete

echo ""
echo "==> デプロイ完了"
echo "    URL: ${APP_URL}/"
echo ""
echo "注意: CloudFront のキャッシュ反映に数分かかる場合があります。"
echo "      Cognito の callback URL に ${APP_URL}/callback が含まれていることを確認してください。"
