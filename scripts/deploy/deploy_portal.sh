#!/usr/bin/env bash
# ETRA Analysis Portal デプロイスクリプト
#
# 使用方法:
#   cd infra/terraform/envs/dev
#   terraform apply -auto-approve
#   cd ../../../../
#   bash scripts/deploy/deploy_portal.sh
#
# 前提:
#   - AWS CLI が設定済みであること
#   - Node.js 20.x / npm が利用可能であること
#   - infra/terraform/envs/dev で terraform apply 済みであること

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PORTAL_DIR="$REPO_ROOT/frontend/portal"
TF_DIR="$REPO_ROOT/infra/terraform/envs/dev"

echo "==> Terraform output を取得中..."
cd "$TF_DIR"

API_ENDPOINT=$(terraform output -raw api_endpoint)
CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain)
COGNITO_USER_POOL_ID=$(terraform output -raw cognito_user_pool_id)
COGNITO_CLIENT_ID=$(terraform output -raw cognito_client_id)
COGNITO_AUTH_DOMAIN=$(terraform output -raw cognito_auth_domain)
FRONTEND_BUCKET=$(terraform output -raw frontend_bucket_name)
REGION="us-east-1"

COGNITO_AUTHORITY="https://cognito-idp.${REGION}.amazonaws.com/${COGNITO_USER_POOL_ID}"
COGNITO_HOSTED_UI_DOMAIN="https://${COGNITO_AUTH_DOMAIN}.auth.${REGION}.amazoncognito.com"
PORTAL_URL="https://${CLOUDFRONT_DOMAIN}/portal/"

echo "  API_ENDPOINT:       $API_ENDPOINT"
echo "  CLOUDFRONT_DOMAIN:  $CLOUDFRONT_DOMAIN"
echo "  FRONTEND_BUCKET:    $FRONTEND_BUCKET"

echo "==> config.js を生成中..."
cat > "$PORTAL_DIR/public/config.js" <<EOF
window.__ETRA_CONFIG__ = {
  apiEndpoint: '${API_ENDPOINT}',
  cognitoAuthority: '${COGNITO_AUTHORITY}',
  cognitoHostedUiDomain: '${COGNITO_HOSTED_UI_DOMAIN}',
  cognitoClientId: '${COGNITO_CLIENT_ID}',
  cognitoRedirectUri: '${PORTAL_URL}',
  cognitoPostLogoutUri: '${PORTAL_URL}',
  region: '${REGION}',
}
EOF

echo "==> npm ビルド中..."
cd "$PORTAL_DIR"
npm ci
npm run build

echo "==> S3 へアップロード中..."
# 静的アセット（コンテンツハッシュ付き）: 1年キャッシュ
aws s3 sync dist/assets/ "s3://${FRONTEND_BUCKET}/portal/assets/" \
  --cache-control "public, max-age=31536000, immutable" \
  --delete

# index.html: キャッシュ無効
aws s3 cp dist/index.html "s3://${FRONTEND_BUCKET}/portal/index.html" \
  --cache-control "no-cache, no-store, must-revalidate"

# config.js: キャッシュ無効
aws s3 cp dist/config.js "s3://${FRONTEND_BUCKET}/portal/config.js" \
  --cache-control "no-cache, no-store, must-revalidate" 2>/dev/null || \
aws s3 cp public/config.js "s3://${FRONTEND_BUCKET}/portal/config.js" \
  --cache-control "no-cache, no-store, must-revalidate"

echo ""
echo "==> デプロイ完了"
echo "    URL: ${PORTAL_URL}"
echo ""
echo "注意: CloudFront のキャッシュ反映に数分かかる場合があります。"
echo "      terraform.tfvars の cognito_callback_urls / cognito_logout_urls に"
echo "      ${PORTAL_URL} が含まれていることを確認してください。"
