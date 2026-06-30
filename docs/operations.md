# 運用手順

## 初回デプロイ手順

### 前提条件

- AWS CLI が設定済みであること（`aws configure`）
- Terraform 1.8+ がインストール済みであること
- Node.js 20.x / Yarn がインストール済みであること
- Python 3.11 がインストール済みであること
- `etra-admin` IAM ユーザーに必要な権限が付与済みであること

### ステップ 1: Terraform state バックエンド初期化（初回のみ）

```bash
cd infra/terraform/global
terraform init
terraform apply
# → S3 バケット (etra-tf-state) と DynamoDB テーブル (etra-tf-lock) が作成される
```

### ステップ 2: 環境設定ファイルの準備

`infra/terraform/envs/dev/terraform.tfvars` を編集して以下を設定する（リポジトリにコミットしないこと）:

```hcl
allowed_email_domains  = ["your-institution.ac.jp"]   # 大学のドメイン
allowed_emails         = [                             # 研究室メンバーのアドレス
  "alice@your-institution.ac.jp",
  "bob@your-institution.ac.jp",
]
alert_emails           = ["admin@your-institution.ac.jp"]
monthly_budget_usd     = "100"
cognito_callback_urls  = ["https://<cloudfront-domain>/portal/"]
cognito_logout_urls    = ["https://<cloudfront-domain>/portal/"]
```

### ステップ 3: インフラデプロイ

```bash
cd infra/terraform/envs/dev
terraform init
terraform plan
terraform apply
```

apply 完了後、以下の出力値を控える:
- `cognito_user_pool_id`
- `cognito_client_id`
- `cloudfront_domain`
- `workspace_bucket_name`
- `healthimaging_datastore_id`

### ステップ 4: OHIF Viewer 設定の更新

`frontend/ohif/platform/app/public/config/app-config.js` の環境変数プレースホルダーを実際の値に更新する:

```javascript
datastoreId: '<healthimaging_datastore_id>',
region: 'us-east-1',
authority: 'https://cognito-idp.us-east-1.amazonaws.com/<cognito_user_pool_id>',
client_id: '<cognito_client_id>',
redirect_uri: 'https://<cloudfront_domain>/callback',
```

### ステップ 5: フロントエンドビルド・デプロイ

```bash
cd frontend/ohif
yarn install
yarn run build

# S3 へアップロード
aws s3 sync platform/app/dist/ s3://<frontend-bucket>/ --delete

# CloudFront キャッシュを無効化
aws cloudfront create-invalidation \
  --distribution-id <distribution-id> \
  --paths "/*"
```

### ステップ 6: Lambda 関数デプロイ

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

cd ../scripts/deploy
./deploy_lambda.sh start_compute
./deploy_lambda.sh stop_compute
./deploy_lambda.sh status_compute
./deploy_lambda.sh workspace_api
./deploy_lambda.sh notify_status
```

### ステップ 7: SNS メール通知の承認

`alert_emails` に設定したアドレスに AWS から確認メールが届く。
メール内の「Confirm subscription」リンクをクリックする。

### ステップ 7.5: 解析ポータルデプロイ

```bash
bash scripts/deploy/deploy_portal.sh
```

terraform.tfvars の `cognito_callback_urls` / `cognito_logout_urls` に
`https://<cloudfront-domain>/portal/` が含まれていることを確認してから実行すること。

### ステップ 8: 動作確認チェックリスト

- [ ] CloudFront URL で OHIF Viewer が表示される
- [ ] `https://<cloudfront-domain>/portal/` で解析ポータルが表示される
- [ ] ポータルのサインアップ画面でホワイトリスト外アドレスが拒否される
- [ ] ホワイトリスト内アドレスで登録・ログインできる
- [ ] Lambda 関数が CloudWatch Logs にロググループを作成している
- [ ] EventBridge スケジュールが有効になっている
- [ ] AWS Budgets のアラートが設定されている
- [ ] CloudTrail が有効になっている

---

## 日常運用

### メンバー追加・削除

**追加**（`terraform.tfvars` を編集して apply するだけ）:

```hcl
# infra/terraform/envs/dev/terraform.tfvars
allowed_emails = [
  "alice@your-institution.ac.jp",
  "bob@your-institution.ac.jp",
  "carol@your-institution.ac.jp",  # ← 追加
]
```

```bash
cd infra/terraform/envs/dev && terraform apply
```

apply 後、メンバーはポータルのサインアップ画面から自分でアカウントを作成できる。
登録完了後、管理者が Cognito コンソールでグループ（`admin` / `user`）に追加する。

**削除**（アクセス停止）:

```bash
# ホワイトリストから削除して apply（新規登録を防ぐ）
# 既存アカウントは Cognito コンソールで無効化する
aws cognito-idp admin-disable-user \
  --user-pool-id <pool-id> \
  --username <email>
```

---

### 解析ノード起動・停止

```bash
# Lambda 経由で起動
aws lambda invoke \
  --function-name etra-dev-start-compute \
  --payload '{"instance_id": "<instance-id>"}' \
  response.json

# Lambda 経由で停止
aws lambda invoke \
  --function-name etra-dev-stop-compute \
  --payload '{"instance_id": "<instance-id>"}' \
  response.json

# EC2 状態確認
aws lambda invoke \
  --function-name etra-dev-status-compute \
  --payload '{"instance_id": "<instance-id>"}' \
  response.json
```

### JupyterLab へのアクセス

```bash
# SSM ポートフォワーディングで接続
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8888"],"localPortNumber":["8888"]}'

# ブラウザで開く
open http://localhost:8888
```

### ログ確認

```bash
# Lambda ログ
aws logs tail /aws/lambda/etra-dev-start-compute --follow
aws logs tail /aws/lambda/etra-dev-stop-compute --follow
aws logs tail /aws/lambda/etra-dev-status-compute --follow
aws logs tail /aws/lambda/etra-dev-workspace-api --follow
aws logs tail /aws/lambda/etra-dev-notify-status --follow

# EC2 userdata ログ（SSM 経由）
aws ssm start-session --target <instance-id>
sudo tail -f /var/log/userdata.log

# CloudTrail イベント確認（直近1時間）
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=ec2.amazonaws.com \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
```

### S3 ワークスペース確認

```bash
aws s3 ls s3://<workspace-bucket>/personal/
aws s3 ls s3://<workspace-bucket>/shared/dropbox/
aws s3 ls s3://<workspace-bucket>/shared/templates/
aws s3 ls s3://<workspace-bucket>/results/
```

---

## インフラ変更手順

```bash
cd infra/terraform/envs/dev
terraform fmt
terraform validate
terraform plan -out=tfplan
# 差分を確認してから適用
terraform apply tfplan
```

---

## 障害対応

### EC2 が停止しない場合

1. CloudWatch ログで Lambda (`etra-dev-stop-compute`) のエラーを確認する。
2. SSM Agent の状態を確認する（`aws ssm describe-instance-information`）。
3. 手動で AWS コンソールから停止する（緊急時のみ）。

### JupyterLab に接続できない場合

1. SSM ポートフォワーディングのセッションが確立されているか確認する。
2. EC2 上で JupyterLab サービスの状態を確認する:
   ```bash
   # SSM セッション経由
   sudo systemctl status jupyterlab
   sudo journalctl -u jupyterlab -n 50
   ```
3. userdata の実行が完了しているか確認する（`/var/log/userdata.log`）。

### S3 dropbox の自動削除が動作しない場合

1. S3 Lifecycle ポリシーが `shared/dropbox/` プレフィックスに設定されているか確認する。
2. バケットのバージョニングが有効な場合、`noncurrent_version_expiration` も設定されているか確認する。

---

## コスト管理

### AWS Budgets アラート設定

Terraform で自動設定済み（`cloudwatch` モジュール）:
- 月間予算の **80% 到達**時にメール通知（実績ベース）
- 月間予算の **100% 超過予測**時にメール通知（予測ベース）
- デフォルト予算上限: `$100/月`（`terraform.tfvars` の `monthly_budget_usd` で変更可能）

### コスト確認コマンド

```bash
# 当月コスト確認
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE

# EC2 の未使用 EBS ボリューム確認
aws ec2 describe-volumes \
  --filters Name=status,Values=available \
  --query "Volumes[].{ID:VolumeId,Size:Size,Created:CreateTime}"
```

### 実施済みコスト最適化（dev 環境）

| 対象 | 変更内容 | 削減額（目安） |
|------|---------|--------------|
| VPC Interface Endpoint | lambda / logs / cognito_idp / sns を削除 | -$29/月 |
| VPC AZ 数 | 2 AZ → 1 AZ（us-east-1a のみ） | -$15/月 |
| **合計** | | **-$44/月** |

> prod 環境では HA のため 2 AZ を維持すること。

### 1か月後コストレビュー計画

運用開始から 1 か月後に以下を評価し、再設計の判断を行う。

| 評価項目 | 確認内容 | 判断基準 |
|---------|---------|---------|
| EC2 稼働時間 | 解析ノードの平均稼働時間/日 | 常時起動が多い場合はリザーブドインスタンス検討 |
| S3 ストレージ量 | personal/ / results/ の増加速度 | 急増している場合はライフサイクル設定を追加 |
| HealthImaging アクセス | データストアへのアクセス頻度 | 高頻度なら S3 へのキャッシュ層を検討 |
| EFS / FSx 必要性 | 複数 EC2 間でのファイル共有需要 | 需要があれば EFS 導入を検討 |
| Lambda 実行回数 | 各関数の呼び出し回数 | 想定外に多い場合は利用パターンを調査 |

---

## バックアップ

- HealthImaging データは AWS 側で冗長化（追加設定不要）。
- S3 バケットはバージョニングを有効化済み。
- Terraform state は S3 リモートバックエンド（`etra-tf-state`）で管理。
- EC2 の作業データは停止前に S3 へ自動同期（`ws-sync-on-shutdown` サービス）。
