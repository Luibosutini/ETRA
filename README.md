# ETRA — 医用画像解析基盤

ETRA は、AWS 上で DICOM 画像の正式保管・閲覧と、MATLAB / Python による解析実行環境を統合する医用画像解析基盤です。DICOM は AWS HealthImaging と OHIF Viewer で扱い、解析は S3 ワークスペースとオンデマンド EC2 解析ノードに分離します。

構成はハイブリッド型です。閲覧、認証、API、監査はマネージドサービスを優先し、GUI を伴う MATLAB や JupyterLab は EC2 + Amazon DCV / SSM port forwarding で扱います。詳細な構成図は [アーキテクチャ設計: 全体構成](docs/architecture.md#全体構成) を参照してください。

## 設計思想

この節は [CLAUDE.md の採用方針](CLAUDE.md#採用方針)、[非採用方針](CLAUDE.md#非採用方針)、[行動原則](CLAUDE.md#行動原則) を出典にしています。詳細は [docs/architecture.md](docs/architecture.md) と [docs/security.md](docs/security.md) を参照してください。

- **方針:** DICOM 正式保管・閲覧と解析用ワークスペースを分離する。**理由:** 原本 DICOM の保管責務と、頻繁に読み書きされる解析入力・結果の責務を混在させないため。
- **方針:** HealthImaging を解析主ストレージにしない。**理由:** HealthImaging は DICOM 保管・検索・閲覧の中核であり、解析中の作業ファイル、テンプレート、結果保存は S3 系ワークスペースの方が運用しやすいため。
- **方針:** 高コスト解析ノードはオンデマンド起動にする。**理由:** MATLAB / JupyterLab 用 EC2 を常時起動せず、利用時だけ起動・停止できる設計にしてコストを制御するため。
- **方針:** EC2 へのアクセスは SSM port forwarding 経由に限定する。**理由:** SSH key、固定 IP、inbound Security Group rule を不要にし、接続経路を AWS Systems Manager に集約するため。
- **方針:** MATLAB GUI は EC2 + Amazon DCV 前提で扱う。**理由:** GUI を必要とする既存資産は Lambda / Fargate に載せず、デスクトップセッションを提供できる実行基盤で扱う必要があるため。
- **方針:** `personal/`, `shared/dropbox/`, `shared/templates/`, `results/` の責務を分ける。**理由:** 個人作業、一時共有、正式テンプレート、実行結果を分離し、誤共有や恒久保管の混入を防ぐため。
- **方針:** 主要操作の監査可能性を初期設計に含める。**理由:** 起動停止、画像アクセス、解析開始、結果保存を追跡できない仕組みを正式機能にしないため。

## 全体像

| 機能 | 主なサービス / 実装 |
|------|--------------------|
| DICOM 正式保管・閲覧 | AWS HealthImaging + OHIF Viewer 3.x |
| 解析ポータル | `frontend/portal/`、Vite + React、CloudFront `/portal/` |
| DICOM 閲覧 UI | `frontend/ohif/`、CloudFront `/ohif/` |
| 解析実行 | EC2 解析ノード、JupyterLab、Amazon DCV |
| ワークスペース | Amazon S3、`personal/` / `shared/` / `results/` |
| API・自動化 | API Gateway HTTP API + Python 3.11 Lambda |
| 認証・認可 | Amazon Cognito、`admin` / `user` group |
| EC2 接続 | AWS Systems Manager Session Manager port forwarding |
| インフラ管理 | Terraform 1.8+、Packer |
| 監視・監査 | CloudWatch、CloudTrail、EventBridge、SNS、AWS Budgets |

## 主要概念

全用語は [docs/glossary.md](docs/glossary.md) を参照してください。

- `workspace`: S3 上の解析用作業領域。ポータルと解析ノードの入出力をつなぐ。
- `personal/<uid>/`: Cognito user `sub` ごとの個人作業領域。
- `shared/dropbox/` / `shared/templates/`: 一時共有領域と正式テンプレート置き場。
- `compute node`: JupyterLab、DCV、解析ライブラリを持つ EC2 解析ノード。
- `SSM port forwarding`: localhost から JupyterLab `8888` や DCV `8443` へ接続する方式。
- `presigned URL`: S3 object の一時的な upload / download URL。
- `admin` / `user` group: Cognito の権限分離。admin は管理機能、user は自分の解析操作が中心。
- `HealthImaging datastore`: DICOM ImageSet の正式保管先。

## ディレクトリ構造

```text
.
├── frontend/
│   ├── portal/             # Vite + React 解析ポータル
│   └── ohif/               # OHIF Viewer 3.x（DICOM 閲覧）
├── backend/
│   ├── lambda/             # Lambda 関数（13 関数）
│   ├── shared/             # 認証、レスポンス、AWS client 共通処理
│   └── tests/              # pytest テスト
├── infra/terraform/
│   ├── global/             # Terraform state バックエンド（S3 + DynamoDB）
│   ├── modules/            # 再利用可能な Terraform module
│   └── envs/dev/           # dev 環境エントリーポイント
├── analysis/
│   ├── python/             # Python 解析スクリプト
│   ├── matlab/             # MATLAB スクリプト・GUI 資産
│   └── notebooks/          # Jupyter Notebook テンプレート
├── packer/                 # 解析ノード AMI ビルド
├── docs/                   # 設計・運用・拡張ドキュメント
└── config/                 # 環境別設定ファイル
```

## コンポーネント概観

### Backend Lambda

Lambda は 13 関数です。API、env、内部関数の詳細は [開発者リファレンス: Backend Lambda 関数](docs/reference.md#backend-lambda-関数) を参照してください。

| 関数 | 機能カテゴリ | 概要 |
|------|--------------|------|
| `start_compute` | compute 制御 | ユーザーの解析ノードを起動、または既存 node を再利用する。 |
| `stop_compute` | compute 制御 | 権限に応じて解析ノードを停止する。 |
| `status_compute` | compute 制御 | 解析ノードの状態と SSM 接続状態を返す。 |
| `cleanup_compute` | compute 制御 | idle node の停止と長期 stopped node の terminate を定期実行する。 |
| `restart_jupyter` | compute / connect | JupyterLab の修復・再起動と DCV token 発行を扱う。 |
| `workspace_api` | workspace | S3 workspace の一覧、upload URL、download URL、削除を扱う。 |
| `dicom_api` | DICOM | HealthImaging ImageSet を検索し、study 一覧を返す。 |
| `connect_api` | connect | SSM port forwarding 用の一時 credential を発行する。 |
| `admin_api` | admin | Cognito user / group 管理と EC2 terminate を扱う。 |
| `logs_api` | admin / logs | CloudWatch Logs の group と event を返す。 |
| `cognito_pre_signup` | Cognito trigger | signup 前に email domain と allowlist を検証する。 |
| `cognito_post_confirmation` | Cognito trigger | email 確認済みユーザーを `user` group に追加する。 |
| `notify_status` | notify | EC2 state-change event を SNS に通知する。 |

### Frontend

| パス | 役割 |
|------|------|
| `frontend/portal/` | 解析ノード制御、workspace 操作、DICOM study 検索、接続情報生成、admin/logs 画面を持つ解析ポータル。 |
| `frontend/ohif/` | HealthImaging datastore の study を閲覧する OHIF Viewer。 |

### Infra

Terraform は `infra/terraform/envs/dev/main.tf` から 12 module を呼び出します。module 一覧と責務は [アーキテクチャ設計: Terraform モジュール構成](docs/architecture.md#terraform-モジュール構成) を参照してください。

| パス | 役割 |
|------|------|
| `infra/terraform/global/` | remote state 用 S3 bucket と DynamoDB lock table。 |
| `infra/terraform/modules/` | `vpc`, `s3`, `iam`, `cognito`, `healthimaging`, `ec2`, `lambda`, `eventbridge`, `cloudtrail`, `cloudwatch`, `apigateway`, `cloudfront`。 |
| `infra/terraform/envs/dev/` | dev 環境の provider、module wiring、variables、outputs。 |

### 解析ノード AMI

Packer は 6 つの script stage で解析ノード AMI を作成し、最後に SSM Agent の登録情報を cleanup します。拡張手順は [拡張ガイド: 解析ノード AMI を拡張する](docs/extending.md#解析ノード-ami-を拡張する) を参照してください。

| stage | script | 概要 |
|-------|--------|------|
| 1 | `01-base-packages.sh` | Amazon Linux package、Python 3.11、開発 tool。 |
| 2 | `02-desktop-xfce.sh` | XFCE desktop と DCV virtual session 用設定。 |
| 3 | `03-python-jupyter.sh` | Python 解析 library と JupyterLab。 |
| 4 | `04-dcv-server.sh` | Amazon DCV server と web viewer。 |
| 5 | `05-systemd-services.sh` | `jupyterlab.service`、workspace sync、SSM agent。 |
| 6 | `06-helper-scripts.sh` | `ws-sync-down`, `ws-sync-up`, `dcv-token`。 |

## セットアップ

詳細な初回手順と確認項目は [運用手順: 初回デプロイ手順](docs/operations.md#初回デプロイ手順) を参照してください。

### 前提条件

- AWS CLI（設定済み）
- Terraform 1.8+
- Packer 1.10+（解析ノード AMI を build する場合）
- Node.js 20.x / npm / Yarn
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
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集（allowed_email_domains, allowed_emails, alert_emails, ami_id 等）

terraform init
terraform plan
terraform apply
```

解析ノード用 AMI が未作成の場合は、Packer で AMI を build し、出力された AMI ID を `infra/terraform/envs/dev/terraform.tfvars` の `ami_id` に設定してから再度 `terraform apply` します。

```bash
bash scripts/deploy/build_ami.sh
```

### 3. フロントエンドビルド・デプロイ

解析ポータルと OHIF Viewer は別々に build / deploy します。

```bash
# 解析ポータル（frontend/portal -> /portal/）
bash scripts/deploy/deploy_portal.sh

# OHIF Viewer（frontend/ohif -> /ohif/）
bash scripts/deploy/deploy_ohif.sh
```

### 4. Lambda デプロイ

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cd ..

bash scripts/deploy/deploy_lambda.sh
```

## 解析ノードへのアクセス

解析ノード（EC2）への接続は SSM port forwarding 経由のみです。SSH、固定 IP、inbound Security Group rule は不要です。ポータルの Connect 画面は一時 credential 入りの接続 script を生成します。

```bash
# JupyterLab へのポートフォワーディング
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8888"],"localPortNumber":["8888"]}'

# ブラウザで開く
open http://localhost:8888
```

DCV へ接続する場合は port `8443` を転送します。

```bash
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8443"],"localPortNumber":["8443"]}'
```

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

## ドキュメント

| ドキュメント | 内容 |
|-------------|------|
| [docs/glossary.md](docs/glossary.md) | 用語集。workspace、compute node、Cognito group、HealthImaging など。 |
| [docs/reference.md](docs/reference.md) | 開発者リファレンス。Lambda 13 関数、shared、API、env、Terraform variables、テスト。 |
| [docs/extending.md](docs/extending.md) | 拡張ガイド。新 Lambda / API / Terraform module / AMI の追加手順。 |
| [docs/architecture.md](docs/architecture.md) | アーキテクチャ設計。全体構成、責務、ネットワーク、Terraform module。 |
| [docs/operations.md](docs/operations.md) | 運用手順。初回デプロイ、日常運用、障害対応、コスト管理。 |
| [docs/requirements.md](docs/requirements.md) | 要件定義。機能要件、非機能要件、制約事項。 |
| [docs/security.md](docs/security.md) | セキュリティ設計。IAM、ネットワーク、認証、暗号化、監査。 |
| [CHANGELOG.md](CHANGELOG.md) | 変更履歴。 |

## 拡張するには

新しい Lambda、API endpoint、Terraform module、解析ノード AMI の変更は [docs/extending.md](docs/extending.md) から始めてください。既存の関数・環境変数・API 仕様は [docs/reference.md](docs/reference.md)、責務境界とネットワーク方針は [docs/architecture.md](docs/architecture.md) に集約しています。

## 未確定事項

MATLAB ライセンス方針は [アーキテクチャ設計](docs/architecture.md#コンポーネント責務) の通り、東海大学 Campus-Wide Individual ライセンスで確定しています。EC2 + DCV 上で各ユーザーが MathWorks アカウント認証を行う前提です。

- EC2 インスタンスタイプ（dev 既定は `t3.xlarge`。実利用後に MATLAB / Python の負荷で見直す）
- カスタムドメイン・ACM 証明書
- EFS / FSx for Lustre の採用判断（1 か月運用後に評価）
- WAF レート制限、KMS カスタマーマネージドキー、Cognito MFA 強制の要否
