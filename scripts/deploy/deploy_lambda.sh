#!/usr/bin/env bash
# ETRA Lambda 全関数パッケージ化・デプロイスクリプト
#
# 使用方法:
#   cd infra/terraform/envs/dev
#   terraform apply   # 初回のみ
#   cd ../../../../
#   bash scripts/deploy/deploy_lambda.sh
#
# 前提:
#   - AWS CLI が設定済みであること
#   - infra/terraform/envs/dev で terraform apply 済みであること
#   - zip コマンドが利用可能であること

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend"
LAMBDA_DIR="$BACKEND_DIR/lambda"
SHARED_DIR="$BACKEND_DIR/shared"
TF_DIR="$REPO_ROOT/infra/terraform/envs/dev"
BUILD_DIR="$(python3 -c 'import tempfile; print(tempfile.gettempdir())')/etra-lambda-build"

# ─────────────────────────────────────────
# Terraform output から関数名を取得
# ─────────────────────────────────────────
echo "==> Terraform output を取得中..."
cd "$TF_DIR"

FUNCTION_NAMES_JSON=$(terraform output -json lambda_function_names)
PRE_SIGNUP_FUNC=$(terraform output -raw cognito_pre_signup_function_name)
POST_CONFIRMATION_FUNC=$(terraform output -raw cognito_post_confirmation_function_name)

get_function_name() {
  echo "$FUNCTION_NAMES_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['$1'])"
}

START_COMPUTE_FUNC=$(get_function_name start_compute)
STOP_COMPUTE_FUNC=$(get_function_name stop_compute)
STATUS_COMPUTE_FUNC=$(get_function_name status_compute)
WORKSPACE_API_FUNC=$(get_function_name workspace_api)
NOTIFY_STATUS_FUNC=$(get_function_name notify_status)
ADMIN_API_FUNC=$(get_function_name admin_api)
LOGS_API_FUNC=$(get_function_name logs_api)
CLEANUP_COMPUTE_FUNC=$(get_function_name cleanup_compute)
CONNECT_API_FUNC=$(get_function_name connect_api)

echo "  start_compute:       $START_COMPUTE_FUNC"
echo "  stop_compute:        $STOP_COMPUTE_FUNC"
echo "  status_compute:      $STATUS_COMPUTE_FUNC"
echo "  workspace_api:       $WORKSPACE_API_FUNC"
echo "  notify_status:       $NOTIFY_STATUS_FUNC"
echo "  admin_api:           $ADMIN_API_FUNC"
echo "  logs_api:            $LOGS_API_FUNC"
echo "  cleanup_compute:     $CLEANUP_COMPUTE_FUNC"
echo "  connect_api:         $CONNECT_API_FUNC"
echo "  pre_signup:          $PRE_SIGNUP_FUNC"
echo "  post_confirmation:   $POST_CONFIRMATION_FUNC"

# ─────────────────────────────────────────
# ビルドディレクトリ準備
# ─────────────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ─────────────────────────────────────────
# ヘルパー関数
# ─────────────────────────────────────────

# Python で ZIP を作成する（zip コマンド不要、クロスプラットフォーム対応）
make_zip() {
  local src_dir="$1"
  local zip_path="$2"
  python3 - "$src_dir" "$zip_path" <<'PYEOF'
import sys, os, zipfile
src_dir, zip_path = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(src_dir):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for f in files:
            if not f.endswith(".pyc"):
                filepath = os.path.join(root, f)
                zf.write(filepath, os.path.relpath(filepath, src_dir))
PYEOF
}

# shared モジュール込みの関数 ZIP を作成してデプロイ
# 引数: <関数ディレクトリ名> <エントリーポイント.py> <Lambda 関数名>
deploy_with_shared() {
  local func_dir="$1"
  local entry_file="$2"
  local function_name="$3"
  local pkg_dir="$BUILD_DIR/$func_dir"

  echo ""
  echo "--> $function_name をパッケージ化中..."
  mkdir -p "$pkg_dir"

  cp "$LAMBDA_DIR/$func_dir/$entry_file" "$pkg_dir/"
  cp -r "$SHARED_DIR" "$pkg_dir/shared"

  local zip_path="$BUILD_DIR/${func_dir}.zip"
  make_zip "$pkg_dir" "$zip_path"

  echo "    デプロイ中..."
  aws lambda update-function-code \
    --function-name "$function_name" \
    --zip-file "fileb://$zip_path" \
    --output text --query 'CodeSize' | xargs -I{} echo "    完了: {} bytes"
}

# standalone の関数 ZIP を作成してデプロイ（shared なし）
# 引数: <関数ディレクトリ名> <エントリーポイント.py> <Lambda 関数名>
deploy_standalone() {
  local func_dir="$1"
  local entry_file="$2"
  local function_name="$3"
  local pkg_dir="$BUILD_DIR/$func_dir"

  echo ""
  echo "--> $function_name をパッケージ化中..."
  mkdir -p "$pkg_dir"

  cp "$LAMBDA_DIR/$func_dir/$entry_file" "$pkg_dir/"

  local zip_path="$BUILD_DIR/${func_dir}.zip"
  make_zip "$pkg_dir" "$zip_path"

  echo "    デプロイ中..."
  aws lambda update-function-code \
    --function-name "$function_name" \
    --zip-file "fileb://$zip_path" \
    --output text --query 'CodeSize' | xargs -I{} echo "    完了: {} bytes"
}

# ─────────────────────────────────────────
# 各関数のデプロイ
# ─────────────────────────────────────────
echo ""
echo "==> Lambda 関数をデプロイ中..."

deploy_with_shared "start_compute"  "start_compute.py"  "$START_COMPUTE_FUNC"
deploy_with_shared "stop_compute"   "stop_compute.py"   "$STOP_COMPUTE_FUNC"
deploy_with_shared "status_compute" "status_compute.py" "$STATUS_COMPUTE_FUNC"
deploy_with_shared "workspace_api"  "workspace_api.py"  "$WORKSPACE_API_FUNC"
deploy_with_shared "notify_status"  "notify_status.py"  "$NOTIFY_STATUS_FUNC"
deploy_with_shared "admin_api"       "admin_api.py"       "$ADMIN_API_FUNC"
deploy_with_shared "logs_api"        "logs_api.py"        "$LOGS_API_FUNC"
deploy_with_shared "cleanup_compute" "cleanup_compute.py" "$CLEANUP_COMPUTE_FUNC"
deploy_with_shared "connect_api"     "connect_api.py"     "$CONNECT_API_FUNC"

deploy_standalone "cognito_pre_signup"       "cognito_pre_signup.py"       "$PRE_SIGNUP_FUNC"
deploy_standalone "cognito_post_confirmation" "cognito_post_confirmation.py" "$POST_CONFIRMATION_FUNC"

# ─────────────────────────────────────────
# クリーンアップ
# ─────────────────────────────────────────
rm -rf "$BUILD_DIR"

echo ""
echo "==> デプロイ完了"
echo ""
echo "動作確認:"
echo "  1. ポータルで新規サインアップ → メール確認"
echo "  2. AWS コンソール > Cognito > ユーザープール > ユーザー"
echo "     → user グループに自動追加されていることを確認"
echo "  3. ポータルにログイン → API が 200 を返すことを確認"
