# アーキテクチャ設計

## 全体構成

```
利用者
  │
  ├─ ブラウザ
  │    ├─ OHIF Viewer (CloudFront + WAF)
  │    │    └─ AWS HealthImaging  ←── DICOM 正式保管・閲覧
  │    │
  │    └─ 解析アプリ (CloudFront + WAF)
  │         ├─ Amazon Cognito       ←── 認証（OIDC / Authorization Code + PKCE）
  │         └─ API Gateway + Lambda ←── 起動停止・状態照会・ワークスペース API
  │
  └─ SSM ポートフォワーディング
       └─ EC2（プライベートサブネット）
            ├─ JupyterLab :8888    ←── Python 解析
            ├─ Amazon DCV :8443    ←── MATLAB GUI（MATLAB ライセンス確定後に有効化）
            └─ S3 Workspace        ←── 起動時同期・停止前同期
```

---

## コンポーネント責務

### DICOM 保管・閲覧層
- **AWS HealthImaging**: DICOM の正式保管。解析用ストレージとして直接使用しない。
- **OHIF Viewer 3.x**: Web ブラウザ上での DICOM 閲覧。CloudFront 経由で配信。

### 認証・認可層
- **Amazon Cognito**: ユーザープール管理。
  - セルフサインアップ有効。Pre-signup Lambda がドメイン＋メールホワイトリストで制限
  - `admin` グループ: 全機能へのアクセス
  - `user` グループ: 自分のワークスペース・解析実行のみ
- **認証フロー**: Authorization Code Flow with PKCE（`generate_secret = false`）
- **解析ポータル**: `frontend/portal/` (Vite + React)。CloudFront の `/portal/` パスで配信
- **API Gateway v2 (HTTP API)**: Cognito JWT Authorizer によりトークンを自動検証。Lambda へのエントリーポイント

### API・自動化層
- **AWS Lambda (Python 3.11)**

  | 関数名 | 役割 |
  |--------|------|
  | `start_compute` | EC2 起動、CloudWatch にイベント記録 |
  | `stop_compute` | EC2 停止 |
  | `status_compute` | EC2 状態照会 |
  | `workspace_api` | S3 ワークスペース CRUD |
  | `notify_status` | SNS 経由でメール通知 |

- **Amazon EventBridge**: 平日 22:00 JST に `stop_compute` を自動実行。
- **AWS Systems Manager**: EC2 へのエージェントレスアクセス。inbound SG ルール不要。

### 解析実行層
- **Amazon EC2 (Amazon Linux 2023)**
  - プライベートサブネット配置、パブリック IP なし
  - 起動テンプレートによりオンデマンド起動
  - JupyterLab は systemd サービスとして起動（`127.0.0.1:8888`）
  - 起動時に S3 から personal/ を同期、停止前に S3 へ同期
- **Amazon DCV**: EC2 上の GUI セッション配信。App Designer 使用のため必須。DCV は EC2 上では無償。
- **SSM ポートフォワーディング**: JupyterLab・DCV へのアクセス経路

**MATLAB ライセンス方針（確定）**
- 東海大学 Campus-Wide **Individual** ライセンス。クラウド（EC2）利用可。
- ライセンスサーバー不要。VPN 不要。各ユーザーが MathWorks アカウントで個別認証。
- 同時利用制限なし。全製品（Simulink / Parallel Computing Toolbox 等）利用可。
- EC2 起動後、ユーザーは DCV セッション内で `matlab` を起動しアカウント認証を行う。

### ストレージ層

| 用途 | サービス | バケット名 |
|------|---------|-----------|
| DICOM 正式保管 | AWS HealthImaging | — |
| 解析ワークスペース | Amazon S3 | `etra-<env>-workspace` |
| フロントエンド配信 | Amazon S3 | `etra-<env>-frontend` |
| アクセスログ | Amazon S3 | `etra-<env>-access-logs` |
| Terraform state | Amazon S3 | `etra-tf-state` |
| EC2 OS / アプリ | Amazon EBS (gp3, 暗号化) | — |

### 監視・監査層
- **Amazon CloudWatch**: Lambda エラーアラーム、EC2 CPU 高負荷アラーム、SNS 通知。
- **AWS CloudTrail**: 全 API 操作の監査ログ（S3 保存）。
- **AWS Budgets**: 月間コスト上限アラート（デフォルト $100）。

---

## ネットワーク構成

```
VPC (10.0.0.0/16)
├── Public Subnets (10.0.101.0/24, 10.0.102.0/24)
│   └── Internet Gateway
│
└── Private Subnets (10.0.1.0/24, 10.0.2.0/24)
    ├── EC2 解析ノード（inbound SG ルールなし）
    ├── Lambda 関数
    └── VPC Endpoints
         ├── S3 (Gateway)
         ├── SSM (Interface)
         ├── SSMMessages (Interface)
         ├── EC2Messages (Interface)
         └── Lambda (Interface)
```

**EC2 アクセス経路**
- SSH (22) は Security Group で開放しない
- JupyterLab: `aws ssm start-session --document-name AWS-StartPortForwardingSession --parameters '{"portNumber":["8888"],...}'`
- DCV (MATLAB): 同上、ポート 8443

---

## ワークスペース S3 構造

```
s3://etra-<env>-workspace/
├── personal/<instance-id>/    # 各ユーザーの作業領域（EC2 起動時に同期）
├── shared/
│   ├── dropbox/               # 一時共有（S3 Lifecycle で 24 時間後に自動削除）
│   └── templates/             # 共有テンプレート（恒久保管）
└── results/<instance-id>/     # 実行結果
```

---

## Terraform モジュール構成

```
infra/terraform/
├── global/          # state バックエンド（S3 + DynamoDB）
├── modules/
│   ├── vpc/         # VPC・サブネット・VPC Endpoints・Security Groups
│   ├── s3/          # ワークスペース・フロントエンド・ログバケット
│   ├── iam/         # Lambda・EC2 実行ロール
│   ├── cognito/     # ユーザープール・Pre-signup Lambda（ドメイン＋ホワイトリスト）
│   ├── healthimaging/ # HealthImaging データストア（awscc プロバイダー）
│   ├── ec2/         # 起動テンプレート・userdata
│   ├── lambda/      # 5 関数デプロイ
│   ├── eventbridge/ # 自動停止スケジュール
│   ├── cloudtrail/  # 監査ログ
│   ├── cloudwatch/  # アラーム・SNS・Budgets
│   ├── cloudfront/  # CloudFront Distribution・WAF・OAC（ポータル配信ルール含む）
│   └── apigateway/  # HTTP API v2・Cognito JWT Authorizer・Lambda 統合
└── envs/
    └── dev/         # dev 環境エントリーポイント
```

---

## TODO / 未確定事項

- MATLAB ライセンス方針（Academic 個人 / キャンパスライセンス）→ 確認中
- EC2 インスタンスタイプ（MATLAB ライセンス確定後に固定。現在 `t3.xlarge` 仮）
- Amazon DCV セットアップ（MATLAB ライセンス確定後に有効化）
- EFS / FSx for Lustre の採用判断（1 か月運用後に評価）
- カスタムドメイン・ACM 証明書（現在 CloudFront デフォルト証明書）
