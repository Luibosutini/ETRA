# ETRA IAM ポリシー

## ファイル一覧

### 管理者ユーザー（4 ポリシーをロールにアタッチ）

| ファイル | 内容 |
|---------|------|
| `etra-admin-compute.json` | EC2 起動停止・SSM ポートフォワーディング |
| `etra-admin-users.json` | Cognito ユーザー管理 |
| `etra-admin-observe.json` | Lambda 呼び出し・S3・CloudWatch・コスト閲覧 |
| `etra-admin-iam.json` | IAM ポリシー作成・アタッチ、初期 S3/DynamoDB 作成（セットアップ用） |

### CI/CD デプロイ（push ごと）

| ファイル | 内容 |
|---------|------|
| `etra-cicd-deploy.json` | フロントエンド S3 デプロイ・CloudFront 無効化・Lambda コード更新 |

### CI/CD Terraform（インフラ変更時のみ、4 ポリシーをアタッチ）

| ファイル | 内容 |
|---------|------|
| `etra-cicd-tf-backend.json` | Terraform state S3・DynamoDB ロック |
| `etra-cicd-tf-network.json` | VPC・サブネット・SG・EC2 起動テンプレート |
| `etra-cicd-tf-app.json` | IAM・Lambda・Cognito・HealthImaging |
| `etra-cicd-tf-platform.json` | S3 バケット・CloudWatch・CloudTrail・SNS・WAF・CloudFront |

---

## AWS CLI での作成・アタッチ手順

### 管理者ポリシーを作成してロールにアタッチ

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_NAME=<管理者のロール名>

for name in etra-admin-compute etra-admin-users etra-admin-observe etra-admin-iam; do
  aws iam create-policy \
    --policy-name ${name} \
    --policy-document file://config/iam/${name}.json

  aws iam attach-role-policy \
    --role-name ${ROLE_NAME} \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${name}
done
```

### CI/CD Terraform ポリシーを作成してロールにアタッチ

```bash
ROLE_NAME=<GitHub Actions のロール名>

for name in etra-cicd-deploy etra-cicd-tf-backend etra-cicd-tf-network etra-cicd-tf-app etra-cicd-tf-platform; do
  aws iam create-policy \
    --policy-name ${name} \
    --policy-document file://config/iam/${name}.json

  aws iam attach-role-policy \
    --role-name ${ROLE_NAME} \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${name}
done
```

---

## GitHub Actions OIDC 連携（推奨）

シークレット不要で GitHub Actions から AWS を操作できます。

### 信頼ポリシー（Trust Policy）

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:Luibosutini/utls:*"
        }
      }
    }
  ]
}
```

### ワークフロー設定例

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::<ACCOUNT_ID>:role/<GitHub Actions のロール名>
      aws-region: us-east-1
```
