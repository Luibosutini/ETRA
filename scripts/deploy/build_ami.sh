#!/usr/bin/env bash
# ETRA カスタム AMI ビルドスクリプト（Packer）
#
# 前提:
#   - packer が PATH にあること（https://developer.hashicorp.com/packer/install）
#   - AWS 認証情報が設定済みであること
#   - infra/terraform/envs/dev で terraform apply 済みであること
#     （パブリックサブネット ID を terraform output から自動取得する）
#
# 使い方:
#   bash scripts/deploy/build_ami.sh
#
# ビルド後:
#   出力された AMI ID を infra/terraform/envs/dev/terraform.tfvars に設定し、
#   terraform apply を実行すること。
#     ami_id = "ami-xxxxxxxxxxxxxxxxx"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PACKER_DIR="$REPO_ROOT/packer"
TF_DIR="$REPO_ROOT/infra/terraform/envs/dev"

# ─────────────────────────────────────────
# packer コマンドの確認
# ─────────────────────────────────────────
if ! command -v packer &>/dev/null; then
  echo "ERROR: packer コマンドが見つかりません。"
  echo "  インストール方法: https://developer.hashicorp.com/packer/install"
  exit 1
fi

echo "packer バージョン: $(packer version)"

# ─────────────────────────────────────────
# Terraform output からパブリックサブネット ID を取得
# ─────────────────────────────────────────
echo ""
echo "==> Terraform output からパブリックサブネット ID を取得中..."
cd "$TF_DIR"

PUBLIC_SUBNET_ID=$(terraform output -json public_subnet_id 2>/dev/null | \
  python3 -c "import sys,json; print(json.load(sys.stdin))" 2>/dev/null || echo "")

if [ -z "$PUBLIC_SUBNET_ID" ]; then
  echo ""
  echo "  terraform output に public_subnet_id が見つかりません。"
  echo "  Packer ビルドにはインターネットアクセス可能なパブリックサブネットが必要です。"
  echo ""
  read -rp "  パブリックサブネット ID を入力してください (subnet-xxxxxxxx): " PUBLIC_SUBNET_ID
fi

echo "  builder_subnet_id: $PUBLIC_SUBNET_ID"

# ─────────────────────────────────────────
# Packer ビルド
# ─────────────────────────────────────────
cd "$PACKER_DIR"

echo ""
echo "==> Packer の初期化..."
packer init .

echo ""
echo "==> AMI をビルド中（20〜30 分かかることがあります）..."
packer build \
  -var "builder_subnet_id=$PUBLIC_SUBNET_ID" \
  .

# ─────────────────────────────────────────
# 完了メッセージ
# ─────────────────────────────────────────
echo ""
echo "==> ビルド完了"
echo ""
echo "次のステップ:"
echo "  1. 上記に出力された AMI ID をコピーする（ami-xxxxxxxxxxxxxxxxx）"
echo "  2. infra/terraform/envs/dev/terraform.tfvars に追記または更新:"
echo "       ami_id = \"ami-xxxxxxxxxxxxxxxxx\""
echo "  3. terraform apply を実行する:"
echo "       cd infra/terraform/envs/dev && terraform apply"
echo ""
