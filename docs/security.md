# セキュリティ設計

## IAM 設計方針

- 最小権限原則を遵守する。
- 本番用 IAM 権限を広く取らない（禁止事項 #5）。
- ユーザーが EC2 を直接自由起動できる権限を付与しない（禁止事項 #8）。
- Lambda 実行ロールは関数ごとに分離し、必要なリソースのみアクセス可能にする。

### ロール設計（概要）

| ロール | 用途 | 主な権限 |
|--------|------|---------|
| `lambda-start-compute` | EC2 起動 Lambda | `ec2:StartInstances`, `ssm:StartAutomationExecution` |
| `lambda-stop-compute` | EC2 停止 Lambda | `ec2:StopInstances` |
| `lambda-workspace-api` | S3 操作 Lambda | `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`（ワークスペースバケットのみ） |
| `lambda-status-compute` | 状態照会 Lambda | `ec2:DescribeInstances` |
| `ec2-analysis-node` | EC2 インスタンスロール | S3 ワークスペースバケット読み書き、SSM エージェント |
| `cognito-admin` | 管理者グループ | 全機能 |
| `cognito-user` | 一般利用者グループ | 自分の `personal/` と `shared/` への読み書き、結果保存 |

---

## ネットワークセキュリティ

- EC2 はパブリックサブネットに配置しない。
- EC2 へのアクセスは Amazon DCV（ポート 8443）または Systems Manager Session Manager 経由のみ。
- インバウンドの SSH（22 番ポート）を Security Group で開放しない。
- S3 / HealthImaging / Lambda へは VPC エンドポイント経由でアクセスする。
- OHIF Viewer は CloudFront + WAF 経由で公開する。

---

## シークレット管理

- DB パスワード、API キー、トークンは AWS Secrets Manager に保管する。
- 環境依存の設定値は AWS Systems Manager Parameter Store（SecureString）を使用する。
- コードや Terraform state にシークレットを直接含めない。

---

## 暗号化

| 対象 | 暗号化方式 |
|------|-----------|
| S3 バケット | SSE-S3 または SSE-KMS |
| EBS ボリューム | AWS KMS |
| HealthImaging | AWS マネージドキー |
| 通信（TLS） | TLS 1.2 以上 |

---

## 監査・ログ

- **CloudTrail**: 全リージョンで有効化し、S3 バケットへ保存する。
- **CloudWatch Logs**: Lambda・EC2 のアプリケーションログを収集する。
- **S3 アクセスログ**: ワークスペースバケットのアクセスログを有効化する。
- HealthImaging へのアクセスは CloudTrail で追跡可能にする。
- 監査ログが取れない仕組みを正式採用しない（禁止事項 #7）。

---

## インシデント対応

1. CloudTrail / CloudWatch Alarm で異常を検知する。
2. 該当 EC2 を Systems Manager 経由で隔離（Security Group 変更）する。
3. Secrets Manager でクレデンシャルをローテーションする。
4. インシデント内容を `CHANGELOG.md` に記録する。

---

## TODO / 未確定事項

- WAF ルールセットの詳細（OWASP ルールグループの適用範囲）
- KMS キー管理ポリシー（カスタマーマネージドキーの採用判断）
- Cognito MFA 強制の要否
