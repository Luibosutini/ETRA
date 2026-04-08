# 運用手順

## 日常運用

### 解析ノード起動・停止

```bash
# Lambda 経由で起動（SSM Automation）
aws ssm start-automation-execution \
  --document-name "StartComputeNode" \
  --parameters "InstanceId=<instance-id>"

# Lambda 経由で停止
aws ssm start-automation-execution \
  --document-name "StopComputeNode" \
  --parameters "InstanceId=<instance-id>"

# EC2 状態確認
aws ec2 describe-instances \
  --instance-ids <instance-id> \
  --query "Reservations[].Instances[].State.Name"
```

### ログ確認

```bash
# Lambda ログ
aws logs tail /aws/lambda/start_compute --follow
aws logs tail /aws/lambda/stop_compute --follow
aws logs tail /aws/lambda/workspace_api --follow

# CloudTrail イベント確認（直近1時間）
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=ec2.amazonaws.com \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
```

### S3 ワークスペース確認

```bash
# ワークスペース一覧
aws s3 ls s3://<workspace-bucket>/personal/
aws s3 ls s3://<workspace-bucket>/shared/dropbox/
aws s3 ls s3://<workspace-bucket>/shared/templates/
aws s3 ls s3://<workspace-bucket>/results/
```

---

## デプロイ手順

### インフラ変更

```bash
cd infra/terraform
terraform init
terraform fmt
terraform validate
terraform plan -out=tfplan
# レビュー後に適用
terraform apply tfplan
```

### Lambda デプロイ

```bash
cd backend
pip install -r requirements.txt -t lambda/<function-name>/package/
cd scripts/deploy
./deploy_lambda.sh <function-name>
```

### フロントエンドデプロイ

```bash
cd frontend/ohif
npm install
npm run build
# ビルド成果物を S3 / CloudFront へデプロイ
aws s3 sync dist/ s3://<frontend-bucket>/ --delete
```

---

## 障害対応

### EC2 が停止しない場合

1. CloudWatch ログで Lambda (`stop_compute`) のエラーを確認する。
2. SSM Agent の状態を確認する。
3. 手動で EC2 コンソールから停止する（緊急時のみ）。

### S3 dropbox の自動削除が動作しない場合

1. S3 Lifecycle ポリシーが `shared/dropbox/` プレフィックスに設定されているか確認する。
2. EventBridge スケジュールが有効か確認する。

---

## コスト管理

- 月次で EC2 / S3 / HealthImaging のコストをレビューする。
- 未使用の EBS ボリュームを定期的に削除する。
- 1 か月運用後にストレージ・計算基盤の再設計を判断する（`requirements.md` 参照）。

---

## バックアップ

- HealthImaging データは AWS 側で冗長化。
- S3 バケットはバージョニングを有効化する。
- Terraform state は S3 リモートバックエンドで管理する。
