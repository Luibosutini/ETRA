# TODO

タスク管理ファイル。完了したタスクは削除せず `[x]` に変更する。
詳細な設計・議論は `docs/` 配下の各ファイルに記載する。

---

## 🔴 今すぐ対応（デプロイが機能しない）

- [x] Lambda デプロイスクリプト作成（`scripts/deploy/deploy_lambda.sh`）
- [x] Lambda / Pre-signup Lambda のパッケージ化（deploy_lambda.sh が shared/ 込みでパッケージ化・デプロイ）
- [x] Cognito Post-confirmation Lambda 実装（`backend/lambda/cognito_post_confirmation/`。サインアップ後に `user` グループへ自動追加）

---

## 🟡 近いうちに必要（CLAUDE.md 必須要件）

- [x] アプリ内コード編集（ポータルの Workspace ページにエディタを追加）
      ※ CodeEditorModal.tsx を実装。@uiw/react-codemirror（CodeMirror 6）でシンタックスハイライト付きブラウザ内編集
- [x] ポータルのトークンサイレントリフレッシュ（oidc-client-ts の設定追加）
      ※ automaticSilentRenew: true を設定。リフレッシュトークン（30日）で自動更新

---

## インフラ

- [x] VPC / サブネット設計（Terraform）
- [x] S3 バケット作成（ワークスペース、フロントエンド、Terraform state、ログ）
- [x] IAM ロール・ポリシー定義
- [x] Amazon Cognito ユーザープール・アプリクライアント設定
- [x] AWS HealthImaging データストア作成
- [x] EC2 解析ノード AMI 選定・起動テンプレート作成
- [x] Amazon DCV セットアップ（userdata.sh.tpl に XFCE + DCV インストール・設定・セッション自動作成を実装済み）
- [x] Lambda 関数デプロイ（5 関数）※ placeholder ZIP。実装は backend/lambda/ で行う
- [x] EventBridge スケジュール設定（自動停止：平日 22:00 JST）
- [x] S3 Lifecycle ポリシー設定（`shared/dropbox/` 24 時間 TTL）
- [x] CloudTrail 有効化
- [x] CloudWatch アラーム設定
- [x] API Gateway v2 (HTTP API) + Cognito JWT Authorizer（`infra/terraform/modules/apigateway/`）
- [x] Cognito セルフサインアップ有効化 + メールホワイトリスト（`allowed_emails`）

## フロントエンド

- [x] OHIF Viewer セットアップ（`frontend/ohif/`）
- [x] Cognito 認証統合（app-config.js の oidc セクション）
- [x] CloudFront + WAF 配置（infra/terraform/modules/cloudfront/`）
- [x] 解析ポータル SPA 初期実装（`frontend/portal/`）
- [x] アプリ内コードエディタ（Workspace ページへの CodeMirror 統合）
- [x] ポータルの実行ログ表示（CloudWatch Logs の Lambda / EC2 ログ閲覧）
      ※ LogsPage.tsx + logs_api Lambda（GET /logs, GET /logs/events）を実装。admin のみ表示
- [x] ポータルのグループ管理 UI（管理者が Cognito コンソール不要でグループ割り当て可能に）
      ※ AdminPage.tsx + admin_api Lambda（GET /admin/users, POST/DELETE /admin/users/{username}/groups/{group}）を実装
- [ ] JupyterLab ブラウザ直接接続（NLB + VPC Link 経由。現状は SSM コマンド表示で代替）
- [ ] Connect タブ改善（案A: OS別接続スクリプトダウンロード .bat/.sh + 案B: 初回セットアップガイド埋め込み）

## バックエンド

- [x] Lambda 関数実装（`start_compute`, `stop_compute`, `status_compute`, `workspace_api`, `notify_status`）
- [x] API Gateway v2 対応（auth.py の JWT claims v2 形式、workspace_api の httpMethod / proxy パラメータ）
- [x] pytest テスト作成
- [x] ruff / mypy CI 設定（.github/workflows/backend-ci.yml）
- [x] Cognito Post-confirmation Lambda 実装
- [x] Lambda デプロイスクリプト（`scripts/deploy/deploy_lambda.sh`）

## 解析環境

- [x] EC2 ユーザーデータスクリプト（JupyterLab / Python 環境構築）
- [x] MATLAB ライセンス確認（東海大 Campus-Wide Individual。EC2 クラウド利用可、同時接続制限なし、全製品利用可、ライセンスサーバー不要。各ユーザーが MathWorks アカウントで個別認証）
- [x] MATLAB インスタンスタイプ確定（`m7i.2xlarge`：8 vCPU / 32 GB。M4 Max 相当。per-user 構成）
- [x] Amazon DCV セットアップ（userdata.sh.tpl に XFCE + DCV インストール・設定・セッション自動作成を実装済み）
- [x] 解析テンプレートスクリプト作成（`analysis/python/`, `analysis/matlab/`）
      ※ example_analysis.py, dicom_processing.py, example_analysis.m を作成

## ドキュメント

- [x] README.md 作成
- [x] architecture.md 詳細化
- [x] security.md 詳細化
- [x] operations.md 詳細化

## per-user ハイブリッド構成（案C）

複数ユーザーの同時利用に対応するための構成変更。30人規模・アクティブ割合混在を想定。

### バックエンド
- [x] `start_compute.py` 改修（admin 制限撤廃。`Owner:<user_id>` タグで検索、インスタンスなければ Launch Template から `run_instances`）
- [x] `stop_compute.py` 改修（admin 制限撤廃。`Owner:<user_id>` の自分のインスタンスのみ stop）
- [x] `status_compute.py` 改修（一般ユーザーは自分のインスタンスのみ返す。admin は全台）
- [x] `cleanup_compute.py` 新規作成（`backend/lambda/cleanup_compute/`。CPU < 10% が 30 分継続で stop、7 日間 stopped のインスタンスを terminate。15 分ごと EventBridge で実行）

### フロントエンド
- [x] `DashboardPage.tsx` 改修（起動・停止ボタンを一般ユーザーにも表示。admin は owner 列も表示）

### インフラ
- [x] `infra/terraform/modules/ec2/variables.tf` — `instance_type` デフォルトを `m7i.2xlarge` に変更
- [x] `infra/terraform/modules/eventbridge/main.tf` — 時間ベース自動停止スケジュールを廃止し cleanup_compute の 15 分スケジュールに変更
- [x] `infra/terraform/modules/lambda/main.tf` — `cleanup_compute` Lambda 追加・`LAUNCH_TEMPLATE_ID` 環境変数追加
- [x] `infra/terraform/modules/iam/main.tf` — start_compute に `ec2:RunInstances` / `ec2:CreateTags` / `iam:PassRole` 追加。cleanup_compute ロール新規作成（`ec2:StopInstances` / `ec2:TerminateInstances` / `cloudwatch:GetMetricStatistics`）

---

## 運用準備

- [x] 初回デプロイ手順書確認（`docs/operations.md`）
- [x] コスト上限アラート設定（AWS Budgets）
- [x] 1 か月後コストレビュー計画
- [x] terraform.tfvars 実値記入（`allowed_email_domains`, `allowed_emails`, `cognito_callback_urls` 等）
- [x] SNS メール通知の承認
- [x] terraform apply 実行（S3 CORS + admin_api / logs_api Lambda + VPC Endpoints + per-user 構成変更を一括適用）
- [x] deploy_lambda.sh 実行（全 Lambda をデプロイ）
- [x] deploy_portal.sh 実行（Admin / Logs タブ + per-user Dashboard を含む新ビルドをデプロイ）
- [x] deploy_ohif.sh 実行（OHIF Viewer を S3/CloudFront にデプロイ）

---

## 完了済み

- [x] リポジトリ初期化
- [x] CLAUDE.md 作成
- [x] docs/ フォルダ・初期ドキュメント作成
- [x] Terraform global（state バックエンド）
- [x] Terraform modules（VPC / S3 / IAM / Cognito / HealthImaging / EC2 / Lambda / EventBridge / CloudTrail / CloudWatch / CloudFront / API Gateway）
- [x] Terraform envs/dev（dev 環境エントリーポイント）
- [x] 解析ポータル SPA（`frontend/portal/`）
- [x] Cognito セルフサインアップ + メールホワイトリスト方式
