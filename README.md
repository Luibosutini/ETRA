# ETRA — 医用画像解析基盤

AWS 上に構築する DICOM 画像の保管・閲覧と、MATLAB / Python による解析実行環境を統合した基盤。

---

## 概要

| 機能 | サービス |
|------|---------|
| DICOM 保管・閲覧 | AWS HealthImaging + OHIF Viewer 3.x |
| 解析実行（Python） | EC2 + JupyterLab |
| 解析実行（MATLAB） | EC2 + Amazon DCV（MATLAB ライセンス確定後に有効化） |
| 認証 | Amazon Cognito（管理者 / 一般利用者） |
| ワークスペース | Amazon S3 |
| インフラ管理 | Terraform 1.8+ |

---

## ディレクトリ構造

```
.
├── frontend/ohif/          # OHIF Viewer 3.x（DICOM 閲覧 UI）
├── backend/
│   ├── lambda/             # Lambda 関数（5 関数）
│   └── tests/              # pytest テスト
├── infra/terraform/
│   ├── global/             # Terraform state バックエンド（S3 + DynamoDB）
│   ├── modules/            # 再利用可能モジュール
│   └── envs/dev/           # dev 環境エントリーポイント
├── analysis/
│   ├── python/             # Python 解析スクリプト
│   ├── matlab/             # MATLAB スクリプト・GUI 資産
│   └── notebooks/          # Jupyter Notebook テンプレート
├── docs/                   # 設計ドキュメント
└── config/                 # 環境別設定ファイル
```

---

## セットアップ

### 前提条件

- AWS CLI（設定済み）
- Terraform 1.8+
- Node.js 20.x / Yarn
- Python 3.11

### 1. Terraform state バックエンド初期化（初回のみ）

```bash
cd infra/terraform/global
terraform init
terraform apply
```

### 2. インフラデプロイ

```bash
cd infra/terraform/envs/dev
cp config/dev/terraform.tfvars.example config/dev/terraform.tfvars
# terraform.tfvars を編集（allowed_email_domains, alert_emails 等）

terraform init
terraform plan
terraform apply
```

### 3. フロントエンドビルド・デプロイ

```bash
cd frontend/ohif
yarn install
yarn run build

# S3 + CloudFront へデプロイ
aws s3 sync platform/app/dist/ s3://<frontend-bucket>/ --delete
aws cloudfront create-invalidation --distribution-id <dist-id> --paths "/*"
```

### 4. Lambda デプロイ

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cd ../scripts/deploy
./deploy_lambda.sh <function-name>
```

---

## ワークスペース構造

```
s3://<workspace-bucket>/
├── personal/<instance-id>/   # 各ユーザーの作業領域
├── shared/
│   ├── dropbox/              # 一時共有（24 時間で自動削除）
│   └── templates/            # 共有テンプレート
└── results/<instance-id>/    # 実行結果
```

---

## 解析ノードへのアクセス

解析ノード（EC2）への接続は SSM ポートフォワーディング経由のみ。SSH・固定 IP 不要。

```bash
# JupyterLab へのポートフォワーディング
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8888"],"localPortNumber":["8888"]}'

# ブラウザで開く
open http://localhost:8888
```

---

## 主要コマンド

```bash
# テスト実行
cd backend && pytest

# コード品質チェック
cd backend && ruff check . && mypy .

# インフラ検証
cd infra/terraform/envs/dev && terraform validate && terraform plan

# CloudWatch ログ確認
aws logs tail /aws/lambda/etra-dev-start-compute --follow
```

---

## ドキュメント

| ドキュメント | 内容 |
|-------------|------|
| [docs/architecture.md](docs/architecture.md) | アーキテクチャ設計 |
| [docs/requirements.md](docs/requirements.md) | 要件定義 |
| [docs/operations.md](docs/operations.md) | 運用手順 |
| [docs/security.md](docs/security.md) | セキュリティ設計 |
| [CHANGELOG.md](CHANGELOG.md) | 変更履歴 |

---

## 未確定事項

- MATLAB ライセンス方針（Academic 個人 / キャンパスライセンス）
- EC2 インスタンスタイプ（MATLAB ライセンス確定後に固定）
- カスタムドメイン・ACM 証明書
- EFS / FSx for Lustre の採用判断（1 か月運用後に評価）
