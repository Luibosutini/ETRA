# アーキテクチャ設計

## 全体構成

```
利用者
  │
  ├─ OHIF Viewer (Frontend)
  │    └─ AWS HealthImaging  ←── DICOM 正式保管・閲覧
  │
  └─ 解析アプリ (Frontend)
       ├─ Amazon Cognito       ←── 認証
       ├─ API Gateway + Lambda ←── 起動停止・状態照会・ワークスペース API
       └─ EC2 + Amazon DCV     ←── MATLAB / JupyterLab 実行環境
            └─ S3 Workspace    ←── 解析用ワーク領域
```

---

## コンポーネント責務

### DICOM 保管・閲覧層
- **AWS HealthImaging**: DICOM の正式保管。解析用ストレージとして直接使用しない。
- **OHIF Viewer 3.x**: Web ブラウザ上での DICOM 閲覧。

### 認証・認可層
- **Amazon Cognito**: ユーザープール管理、管理者 / 一般利用者ロール分離。

### 自動化・API 層
- **AWS Lambda (Python 3.11)**
  - `start_compute`: 解析ノード起動
  - `stop_compute`: 解析ノード停止
  - `status_compute`: 状態照会
  - `workspace_api`: S3 ワークスペース操作
  - `notify_status`: 状態変更通知
- **Amazon EventBridge**: スケジュール起動停止、イベントルーティング。
- **AWS Systems Manager**: EC2 へのエージェントレスアクセス、コマンド実行。

### 解析実行層
- **Amazon EC2**: MATLAB GUI 実行ノード（オンデマンド起動）。
- **Amazon DCV**: EC2 上の GUI セッション配信。
- **JupyterLab**: Python 解析用 Web IDE。

### ストレージ層
| 用途 | サービス |
|------|---------|
| DICOM 正式保管 | AWS HealthImaging |
| 解析ワークスペース | Amazon S3 |
| EC2 OS / アプリ | Amazon EBS |
| 共有ファイル（オプション） | Amazon EFS / FSx for Lustre |

### 監視・監査層
- **Amazon CloudWatch**: ログ収集、メトリクス監視、アラーム。
- **AWS CloudTrail**: API 操作の監査ログ。

---

## ネットワーク構成（概要）

- Amazon VPC 内に EC2 / Lambda を配置。
- EC2 は直接インターネット露出しない（Systems Manager / DCV 経由でアクセス）。
- S3 / HealthImaging へは VPC エンドポイント経由でアクセス。

---

## ワークスペース S3 構造

```
s3://<workspace-bucket>/
├─ personal/<user-id>/
├─ shared/
│  ├─ dropbox/        ← 24 時間 TTL（S3 Lifecycle）
│  └─ templates/
└─ results/<user-id>/
```

---

## TODO / 未確定事項

- Terraform モジュール分割方針（envs / modules / global の詳細）
- EC2 インスタンスタイプ（MATLAB ライセンス確定後に固定）
- EFS / FSx の採用判断（1 か月運用後に評価）
