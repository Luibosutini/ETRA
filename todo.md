# TODO

タスク管理ファイル。完了したタスクは削除せず `[x]` に変更する。
詳細な設計・議論は `docs/` 配下の各ファイルに記載する。

---

## インフラ

- [x] VPC / サブネット設計（Terraform）
- [x] S3 バケット作成（ワークスペース、フロントエンド、Terraform state、ログ）
- [x] IAM ロール・ポリシー定義
- [x] Amazon Cognito ユーザープール・アプリクライアント設定
- [x] AWS HealthImaging データストア作成
- [x] EC2 解析ノード AMI 選定・起動テンプレート作成
- [ ] Amazon DCV セットアップ（userdata.sh.tpl にコメントあり。MATLAB 導入後に有効化）
- [x] Lambda 関数デプロイ（5 関数）※ placeholder ZIP。実装は backend/lambda/ で行う
- [x] EventBridge スケジュール設定（自動停止：平日 22:00 JST）
- [x] S3 Lifecycle ポリシー設定（`shared/dropbox/` 24 時間 TTL）
- [x] CloudTrail 有効化
- [x] CloudWatch アラーム設定

## フロントエンド

- [x] OHIF Viewer セットアップ（`frontend/ohif/`）
- [x] Cognito 認証統合（app-config.js の oidc セクション）
- [x] CloudFront + WAF 配置（infra/terraform/modules/cloudfront/）

## バックエンド

- [x] Lambda 関数実装（`start_compute`, `stop_compute`, `status_compute`, `workspace_api`, `notify_status`）
- [x] pytest テスト作成
- [x] ruff / mypy CI 設定（.github/workflows/backend-ci.yml）

## 解析環境

- [x] EC2 ユーザーデータスクリプト（JupyterLab / Python 環境構築）
- [ ] MATLAB ライセンス確認・インスタンスタイプ確定
- [ ] 解析テンプレートスクリプト作成（`analysis/python/`, `analysis/matlab/`）

## ドキュメント

- [x] README.md 作成
- [x] architecture.md 詳細化（Terraform モジュール構成確定後）
- [x] security.md 詳細化（KMS / WAF 方針確定後）

## 運用準備

- [x] 初回デプロイ手順書確認（`docs/operations.md`）
- [x] コスト上限アラート設定（AWS Budgets）
- [x] 1 か月後コストレビュー計画

---

## 完了済み

- [x] リポジトリ初期化
- [x] CLAUDE.md 作成
- [x] docs/ フォルダ・初期ドキュメント作成
- [x] Terraform global（state バックエンド）
- [x] Terraform modules（VPC / S3 / IAM / Cognito / HealthImaging / EC2 / Lambda / EventBridge / CloudTrail / CloudWatch）
- [x] Terraform envs/dev（dev 環境エントリーポイント）
