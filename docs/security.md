# セキュリティ設計

## IAM 設計方針

- 最小権限原則を遵守する。
- ユーザーが EC2 を直接自由起動できる権限を付与しない。
- Lambda 実行ロールは関数ごとに分離し、必要なリソースのみアクセス可能にする。
- EC2 インスタンスロールは S3 ワークスペースバケットと SSM のみに限定する。

### ロール設計

| ロール | 用途 | 主な権限 |
|--------|------|---------|
| `etra-<env>-lambda-start-compute` | EC2 起動 Lambda | `ec2:StartInstances`, `ec2:DescribeInstances`（Project タグ限定） |
| `etra-<env>-lambda-stop-compute` | EC2 停止 Lambda | `ec2:StopInstances`, `ec2:DescribeInstances`（Project タグ限定） |
| `etra-<env>-lambda-status-compute` | 状態照会 Lambda | `ec2:DescribeInstances` |
| `etra-<env>-lambda-workspace-api` | S3 操作 Lambda | `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket`（ワークスペースバケットのみ） |
| `etra-<env>-lambda-notify-status` | 通知 Lambda | `sns:Publish`（通知トピックのみ） |
| `etra-<env>-ec2-analysis` | EC2 インスタンスロール | S3 ワークスペースバケット読み書き、`AmazonSSMManagedInstanceCore` |

### Cognito グループ

| グループ | 対象 | 権限 |
|---------|------|------|
| `admin` | 管理者 | 全機能・全ユーザーのワークスペース参照 |
| `user` | 一般利用者 | 自分の `personal/`・`shared/` 読み書き、解析実行、結果保存 |

---

## ネットワークセキュリティ

### EC2 アクセス制御
- EC2 はプライベートサブネットに配置。パブリック IP なし。
- Security Group の inbound ルールなし（SSH 22 番ポート非開放）。
- アクセスは SSM ポートフォワーディング経由のみ。固定 IP 不要。

```
利用者 → SSM Session Manager → EC2 (127.0.0.1:8888 / 8443)
```

### VPC Endpoints
プライベートサブネットから AWS サービスへのアクセスはすべて VPC Endpoint 経由。
インターネット経由の通信を排除する。

| Endpoint | 種別 |
|----------|------|
| S3 | Gateway |
| SSM | Interface |
| SSMMessages | Interface |
| EC2Messages | Interface |
| Lambda | Interface |

### CloudFront + WAF
- OHIF Viewer は CloudFront 経由でのみ公開。S3 バケットへの直接アクセスは OAC（Origin Access Control）で制限。
- WAF ルール:
  - `AWSManagedRulesCommonRuleSet`: 一般的な脅威（SQLi, XSS 等）をブロック
  - `AWSManagedRulesAmazonIpReputationList`: 既知の不正 IP をブロック

---

## 認証

### Cognito 設定
- **MFA**: OPTIONAL（TOTP）
- **パスワードポリシー**: 12 文字以上、大文字・小文字・数字・記号を含む
- **自己サインアップ**: 有効（Pre-signup Lambda によるホワイトリスト制限あり）
- **メールドメイン制限**: Pre-signup Lambda で許可ドメイン外のサインアップを拒否
- **メールホワイトリスト**: `ALLOWED_EMAILS` 環境変数に登録したアドレスのみ許可（大学全体ドメインを使用する場合に研究室メンバーを限定するために使用）
- **トークン有効期限**: アクセストークン 1 時間、リフレッシュトークン 30 日

### ユーザー登録フロー
```
メンバー → ポータルのサインアップ画面でメールアドレスを入力
→ Pre-signup Lambda がドメイン + ホワイトリストを検証
→ 通過した場合のみ Cognito がメール認証リンクを送信
→ メンバーがリンクをクリックしてアカウント有効化
→ 管理者が Cognito コンソールで適切なグループ（admin / user）に追加
```

### メンバー追加手順
`terraform.tfvars` の `allowed_emails` にアドレスを追加して `terraform apply` するだけでよい。
管理者がユーザーを手動作成する必要はない。

### 認証フロー
Authorization Code Flow with PKCE。クライアントシークレットなし（SPA 向け）。

---

## シークレット管理

- DB パスワード、API キー等は AWS Secrets Manager に保管する。
- 環境依存の設定値は AWS Systems Manager Parameter Store（SecureString）を使用する。
- コードや Terraform state にシークレットを直接含めない。
- `terraform.tfvars` は `.gitignore` に追加し、リポジトリにコミットしない。

---

## 暗号化

| 対象 | 暗号化方式 |
|------|-----------|
| S3 バケット（ワークスペース・フロントエンド・ログ） | SSE-S3 (AES256) |
| S3 バケット（Terraform state） | SSE-S3 (AES256) |
| EBS ボリューム（EC2 ルートディスク） | AWS KMS（gp3, `encrypted = true`） |
| HealthImaging | AWS マネージドキー |
| EC2 メタデータ | IMDSv2 強制（`http_tokens = "required"`） |
| 通信（TLS） | TLS 1.2 以上（CloudFront デフォルト） |

---

## 監査・ログ

- **CloudTrail**: 全リージョンで有効化、S3 バケットへ保存。
- **CloudWatch Logs**: Lambda・EC2 userdata のログを収集（保持期間 30 日）。
- **S3 アクセスログ**: ワークスペースバケットのアクセスログを `etra-<env>-access-logs` バケットへ保存。
- **CloudWatch アラーム**:
  - Lambda 関数エラー（各関数ごと）
  - EC2 CPU 使用率 90% 超過
- 監査ログが取れない仕組みを正式採用しない。

---

## インシデント対応

1. CloudTrail / CloudWatch Alarm で異常を検知する。
2. 該当 EC2 を Systems Manager 経由で隔離（Security Group 変更）する。
3. Secrets Manager でクレデンシャルをローテーションする。
4. インシデント内容を `CHANGELOG.md` に記録する。

---

## TODO / 未確定事項

- WAF ルールセットの詳細（IP レート制限の閾値設定）
- KMS カスタマーマネージドキーの採用判断（現在は AWS マネージドキー）
- Cognito MFA 強制の要否（現在は OPTIONAL）
- カスタムドメイン導入時の ACM 証明書設定
