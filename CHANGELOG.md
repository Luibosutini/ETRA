# CHANGELOG

変更履歴を記録するファイル。CLAUDE.md には変更履歴を記載しない。

形式: [セマンティックバージョニング](https://semver.org/lang/ja/) に準拠する。

---

## [Unreleased]

### Fixed（デプロイ後バグ修正）

- **`cognito:groups` パース修正** (`backend/shared/auth.py`)
  - API Gateway HTTP API が `cognito:groups` を `"[admin user]"`（スペース区切り・括弧付き文字列）で渡す仕様に対応
  - `json.loads` 失敗後のフォールバックでブラケット内容をスペース分割するよう修正
  - 影響: admin_api / logs_api / status_compute / stop_compute すべての admin 判定が正常化

- **admin_api 500 エラー修正** (`infra/terraform/modules/lambda/main.tf`)
  - Cognito ManagedLogin ユーザープールでは `cognito-idp` VPC PrivateLink が非対応のため `admin_api` / `logs_api` を VPC 外に移動
  - `cleanup_compute` も CloudWatch `monitoring` エンドポイントに VPC 内から到達できずタイムアウトしていたため同様に VPC 外に移動

- **stop_compute admin 権限追加** (`backend/lambda/stop_compute/stop_compute.py`)
  - admin ユーザーが他ユーザーのインスタンスを停止できなかった問題を修正
  - admin は Owner タグ不問で全プロジェクトインスタンスを停止可能に

- **cleanup_compute CPU 閾値調整**
  - `IDLE_CPU_THRESHOLD` を 5% → 10% に変更（OS バックグラウンド処理による誤停止を防止）

- **DashboardPage 空状態に起動ボタン追加** (`frontend/portal/src/pages/DashboardPage.tsx`)
  - インスタンス未作成時（初回）に「解析ノードを起動」ボタンを表示
  - 従来はリスト空表示のみで操作不可だった

- **deploy_ohif.sh エンコード修正** (`scripts/deploy/deploy_ohif.sh`)
  - `app-config.js` が Shift-JIS 形式のためバイナリモードで読み書きするよう変更
  - `npm ci` → `npm install --legacy-peer-deps` に変更（package-lock.json 不存在・peer dependency 競合に対応）

### Added（per-user ハイブリッド構成 + OHIF デプロイ対応）

- **Lambda: `cleanup_compute`** (`backend/lambda/cleanup_compute/cleanup_compute.py`)
  - CPU < 5% が 30 分継続 → 自動 stop（CPU アイドル検知）
  - 7 日間 stopped のインスタンスを自動 terminate（EBS コスト削減）
  - EventBridge で 15 分ごとに実行
- **CloudFront: OHIF Viewer ビヘイビア追加** (`infra/terraform/modules/cloudfront/main.tf`)
  - `/ohif`, `/ohif/*` キャッシュビヘイビアを追加
  - `ohif_rewrite` CloudFront Function（拡張子なしパス → `/ohif/index.html`）で SPA ルーティングに対応
  - `/ohif/static/*` は 1 年キャッシュ、`/ohif/config/app-config.js` / `index.html` はキャッシュ無効
- **デプロイスクリプト: `deploy_ohif.sh`** (`scripts/deploy/deploy_ohif.sh`)
  - terraform output から実値を取得し `app-config.js` のプレースホルダを置換
  - `routerBasename` を `/ohif` に設定してビルド
  - S3 の `/ohif/` パスへキャッシュ設定付きでアップロード
- **`shared/aws_clients.py`**: `cloudwatch_client()` を追加

### Changed（per-user ハイブリッド構成）

- **`start_compute.py`** 改修
  - admin 制限を撤廃。全ユーザーが自分のインスタンスを起動可能
  - `Owner:<user_id>` タグでインスタンスを検索。なければ Launch Template から `run_instances`（初回自動作成）
- **`stop_compute.py`** 改修
  - admin 制限を撤廃。`Owner:<user_id>` タグの自分のインスタンスのみ stop 可能
- **`status_compute.py`** 改修
  - 一般ユーザーは自分の `Owner:<user_id>` インスタンスのみ返す。admin は全台返す
  - レスポンスに `owner` フィールドを追加
- **`DashboardPage.tsx`** 改修
  - 起動・停止ボタンを一般ユーザーにも表示（自分のインスタンスのみ操作可）
  - admin は Owner 列を追加表示
- **EventBridge** (`infra/terraform/modules/eventbridge/main.tf`)
  - 時間ベース自動停止スケジュール（平日 22:00 JST）を廃止
  - cleanup_compute の 15 分スケジュールに変更（CPU アイドル検知 + 長期停止 terminate を統合）
- **IAM** (`infra/terraform/modules/iam/main.tf`)
  - `start_compute` ロールに `ec2:RunInstances` / `ec2:CreateTags` / `iam:PassRole` を追加
  - `cleanup_compute` ロールを新規作成（`ec2:StopInstances` / `ec2:TerminateInstances` / `cloudwatch:GetMetricStatistics`）
- **Lambda モジュール** (`infra/terraform/modules/lambda/main.tf`)
  - `cleanup_compute` 関数を追加
  - `start_compute` に `LAUNCH_TEMPLATE_ID` 環境変数を追加
- **EC2 インスタンスタイプ確定** (`infra/terraform/modules/ec2/variables.tf`, `terraform.tfvars`)
  - デフォルトを `t3.xlarge` → `m7i.2xlarge`（8 vCPU / 32 GB、M4 Max 相当、per-user 構成）
- **Cognito callback URL** (`terraform.tfvars`)
  - OHIF 用に `https://<cloudfront-domain>/ohif/callback` を追加

### Fixed

- **ファイルアップロード CORS エラー（API Gateway 401）**
  - `ANY /workspace/{proxy+}` ルートが OPTIONS プリフライトを JWT Authorizer に通し 401 を返していた問題を修正
  - `ANY` を `GET` / `PUT` / `DELETE` の明示的メソッドに分割し、OPTIONS が CORS 設定に委ねられるよう変更
- **S3 CORS 設定追加** (`infra/terraform/modules/s3/main.tf`)
  - workspace バケットに `aws_s3_bucket_cors_configuration` を追加（presigned PUT をブラウザから直接実行可能に）
  - `allowed_origins`: CloudFront ドメイン + localhost:5173

### Added（運用フェーズ）
- **グループ管理 UI** (`frontend/portal/src/pages/AdminPage.tsx`)
  - admin のみ表示。ユーザー一覧（email / ステータス / グループ）を表示
  - 各ユーザーに `admin` / `user` グループの追加・削除ボタン
- **実行ログ表示** (`frontend/portal/src/pages/LogsPage.tsx`)
  - admin のみ表示。Lambda ロググループ一覧ドロップダウン
  - 直近 24 時間のログイベントをタイムスタンプ付きで表示
- **Lambda: `admin_api`** (`backend/lambda/admin_api/admin_api.py`)
  - `GET /admin/users` — Cognito ユーザー一覧（グループ情報付き）
  - `POST /admin/users/{username}/groups/{group}` — グループ追加
  - `DELETE /admin/users/{username}/groups/{group}` — グループ削除
  - admin グループのみ許可
- **Lambda: `logs_api`** (`backend/lambda/logs_api/logs_api.py`)
  - `GET /logs` — Lambda ロググループ一覧
  - `GET /logs/events?group=<name>&limit=<n>` — 最新ログイベント取得（デフォルト 50 件）
  - admin グループのみ許可
- **VPC Endpoints 追加** (`infra/terraform/modules/vpc/main.tf`)
  - `logs` Interface Endpoint: logs_api Lambda が CloudWatch Logs API に到達可能に
  - `cognito-idp` Interface Endpoint: admin_api Lambda が Cognito API に到達可能に
- **Terraform: IAM ロール追加** (`infra/terraform/modules/iam/`)
  - `admin_api` Lambda ロール（cognito-idp: ListUsers / AdminListGroupsForUser / AdminAdd/RemoveUserFromGroup）
  - `logs_api` Lambda ロール（logs: DescribeLogGroups / FilterLogEvents）
  - `cognito_user_pool_arn` 変数を IAM モジュールに追加
- **Terraform: API Gateway ルート追加** (`infra/terraform/modules/apigateway/main.tf`)
  - `GET /admin/users`, `POST /admin/users/{username}/groups/{group}`, `DELETE /admin/users/{username}/groups/{group}`
  - `GET /logs`, `GET /logs/events`
  - 全ルートに Cognito JWT Authorizer を適用
- **解析テンプレートスクリプト** (`analysis/`)
  - `analysis/python/templates/example_analysis.py`: NumPy / SciPy / matplotlib を使った基本解析テンプレ（S3 連携付き）
  - `analysis/python/templates/dicom_processing.py`: AWS HealthImaging から DICOM を取得して処理するテンプレ
  - `analysis/matlab/templates/example_analysis.m`: MATLAB バターワースフィルタ + PSD 解析テンプレ（AWS CLI 経由 S3 連携）
  - `analysis/python/scripts/README.md`, `analysis/matlab/README.md`, `analysis/notebooks/README.md`
- **ポータル ナビゲーション** (`frontend/portal/src/App.tsx`)
  - Admin / Logs タブを追加（admin のみ表示）
- **API クライアント** (`frontend/portal/src/api.ts`)
  - `listUsers`, `addUserToGroup`, `removeUserFromGroup`
  - `listLogGroups`, `getLogEvents`

### Added
- **CloudFront Function** `etra-dev-portal-rewrite` (`infra/terraform/modules/cloudfront/main.tf`)
  - `/portal` および `/portal/` へのリクエストを `/portal/index.html` にリライト
  - S3 がディレクトリインデックスを提供しないことによる AccessDenied（XML 応答）を解消
  - `/portal` と `/portal/` の ordered_cache_behavior を追加し CloudFront Function を適用
- **VPC Endpoints 追加** (`infra/terraform/modules/vpc/main.tf`)
  - `ec2` Interface Endpoint: start/stop/status_compute Lambda が EC2 API（describe/start/stop instances）に到達できるようになった
  - `sns` Interface Endpoint: notify_status Lambda が SNS Publish に到達できるようになった
  - これらが欠如していたため、プライベートサブネット内の Lambda が EC2 API にアクセスできず 503 が発生していた
- **アプリ内コードエディタ** (`frontend/portal/src/pages/CodeEditorModal.tsx`)
  - `@uiw/react-codemirror`（CodeMirror 6）によるブラウザ内ファイル編集を実装
  - 対応拡張子: `.py .m .js .ts .json .yaml .yml .txt .md .sh .r .jl .csv`
  - Python / JavaScript / JSON / Markdown / YAML のシンタックスハイライト（one-dark テーマ）
  - 保存: presigned PUT URL 経由で S3 に直接書き戻し
  - 1 MB 超のファイルは編集不可として保護
  - WorkspacePage の各ファイル行に「編集」ボタンを追加
- **トークンサイレントリフレッシュ** (`frontend/portal/src/auth.ts`, `App.tsx`)
  - `automaticSilentRenew: true` を設定。アクセストークン期限切れ前にリフレッシュトークン（30日）で自動更新
  - リフレッシュ失敗時（リフレッシュトークンも期限切れ）は `signIn()` にフォールバック
  - `onSilentRenewError` ハンドラを App.tsx で購読

### Fixed
- **503 Service Unavailable（ダッシュボード）**: Lambda（プライベートサブネット）が EC2 API エンドポイントに到達できなかった原因は EC2 VPC Endpoint の欠如。追加により `GET /compute/status` が正常に動作する。
- **`/portal/` AccessDenied（XML 応答）**: CloudFront OAC + S3 の組み合わせではディレクトリリクエストが 403 になるため、CloudFront Function でリライトして解消。
- **Cognito Post-confirmation Lambda** (`backend/lambda/cognito_post_confirmation/cognito_post_confirmation.py`)
  - サインアップ・メール確認完了後に `user` グループへ自動追加
  - `PostConfirmation_ConfirmSignUp` トリガーのみ処理。グループ追加失敗時もサインアップは継続
  - Terraform: IAM ロール・ポリシー・Lambda 関数・Cognito トリガー登録を cognito モジュールに追加
- **Lambda デプロイスクリプト** (`scripts/deploy/deploy_lambda.sh`)
  - 全 7 関数（start/stop/status_compute, workspace_api, notify_status, pre_signup, post_confirmation）をパッケージ化してデプロイ
  - 5 つのメイン関数は `shared/` モジュール込みで ZIP 化
  - `terraform output` から関数名を自動取得
- **Amazon DCV セットアップ** (`infra/terraform/modules/ec2/userdata.sh.tpl`)
  - XFCE デスクトップ環境（MATLAB App Designer GUI 必須）
  - NICE DCV Server + Web Viewer インストール（el9 パッケージ）
  - バーチャルセッション自動作成（ec2-user 所有、ポート 8443）
  - `/usr/local/bin/dcv-token`: SSM セッション内でワンタイム接続 URL を生成するヘルパー
- **解析ポータル SPA** (`frontend/portal/`): Vite + React + TypeScript + Tailwind CSS + oidc-client-ts による解析ポータルを新規実装
  - Dashboard ページ: EC2 インスタンス状態確認・起動/停止（admin のみ）
  - Workspace ページ: S3 ファイル一覧・アップロード・ダウンロード・削除
  - Connect ページ: SSM ポートフォワードコマンド生成・クリップボードコピー
  - Cognito PKCE 認証フロー、ハッシュベースルーティング
  - `public/config.js` によるランタイム設定（デプロイ時に実値へ差し替え）
- **API Gateway v2 (HTTP API)** Terraform モジュール (`infra/terraform/modules/apigateway/`)
  - Cognito JWT Authorizer（`requestContext.authorizer.jwt.claims`）
  - 5ルート: `POST /compute/start`, `POST /compute/stop`, `GET /compute/status`, `GET /workspace`, `ANY /workspace/{proxy+}`
  - CORS 設定（CloudFront ドメイン + localhost:5173）
  - CloudWatch Logs 30日保持
- **Lambda モジュール** `function_invoke_arns` output を追加（API Gateway 統合用）
- **CloudFront** ポータル用キャッシュビヘイビアを追加
  - `/portal/index.html`, `/portal/config.js`: キャッシュ無効（no-cache）
  - `/portal/assets/*`: 1年キャッシュ（immutable）
- **デプロイスクリプト** `scripts/deploy/deploy_portal.sh`: terraform output から config.js を生成し S3 へ適切なキャッシュヘッダーでアップロード
- `infra/terraform/envs/dev/outputs.tf` に `api_endpoint`, `frontend_bucket_name` を追加

### Security
- **WAF**: `AWSManagedRulesKnownBadInputsRuleSet` を追加（Log4Shell / CVE-2021-44228 等の既知の不正入力をブロック）
- **`start_compute.py` / `stop_compute.py`**: ログ出力前に instance_id の改行文字をサニタイズ（ログインジェクション対策）
- **全 Lambda 4 関数**: イベントログ出力時に `headers` キーを除外し Authorization トークンの漏洩を防止
- **`frontend/portal/src/App.tsx`**: UI 確認用の認証バイパス（`setAuthed(true)` ハードコード）を削除し、実 OIDC フローを復元
- **`frontend/portal/src/auth.ts`**: Cognito OAuth エンドポイント（authorize / token / logout）を正しい Hosted UI ドメイン（`cognitoHostedUiDomain`）に修正（issuer URL への誤送信を解消）
- **`backend/shared/auth.py`**: `get_caller_groups()` で `cognito:groups` が既に list 型の場合の AttributeError を修正

### Changed
- **`backend/shared/auth.py`**: API Gateway v1 / v2 両形式の JWT claims 取得に対応
  - `_get_claims()` ヘルパーを追加（v2: `authorizer.jwt.claims`、v1: `authorizer.claims` へフォールバック）
  - `get_caller_groups()`: `cognito:groups` の JSON 配列文字列形式（v2）をパース対応
- **`backend/lambda/workspace_api/workspace_api.py`**: API Gateway v2 形式に対応
  - HTTP メソッド取得: `requestContext.http.method` → `httpMethod` フォールバック
  - パスパラメータ: `proxy`（v2 `{proxy+}`）→ `key`（v1）フォールバック
- **`backend/lambda/cognito_pre_signup/cognito_pre_signup.py`**: メールアドレスホワイトリスト機能を追加
  - `ALLOWED_EMAILS` 環境変数を追加（未設定時はドメインチェックのみ）
  - 大学全体ドメインを使用しつつ研究室メンバーのみに登録を限定できるようになった
- **Cognito**: セルフサインアップを有効化（`allow_admin_create_user_only = false`）
  - メンバーが自分でアカウント登録できるようになった（ホワイトリスト制限あり）
- **`infra/terraform/modules/cognito/variables.tf`**: `allowed_emails` 変数を追加
- **`infra/terraform/envs/dev/variables.tf`**: `allowed_emails` 変数を追加
- **`infra/terraform/envs/dev/terraform.tfvars`**: `allowed_emails` 設定欄を追加
- **`backend/shared/auth.ts`** (portal): `getAccessToken` がリダイレクトせず throw するように修正（リダイレクトは App.tsx の init フローのみに限定）
- **`backend/shared/auth.ts`** (portal): `signOut` を Cognito 独自ログアウト URL への直接遷移に修正（BadRequest 解消）
- **`frontend/portal/src/pages/WorkspacePage.tsx`**: ファイル選択時にアップロードキーを自動入力するように修正
- **`infra/terraform/modules/apigateway/main.tf`**: Stage の `access_log_settings` に `format` フィールドを追加（未設定では Terraform apply が失敗する）
- **`frontend/portal/src/pages/ConnectPage.tsx`**: API エラー時のエラー状態を追加（エラー握りつぶし解消）
- **`frontend/portal/package.json`**: `eslint` / `@typescript-eslint` を devDependencies に追加（lint スクリプトが依存関係なしだった問題を修正）
- **`frontend/portal/src/config.ts`** / **`config.js`** / **`deploy_portal.sh`**: `cognitoHostedUiDomain` フィールドを追加

---

### Added（初期構築）
- リポジトリ初期化
- CLAUDE.md（プロジェクト方針・アーキテクチャ概要）
- docs/architecture.md
- docs/requirements.md
- docs/operations.md
- docs/security.md

---

<!-- 以降はリリース時に追記する -->
<!-- 例:
## [0.1.0] - YYYY-MM-DD
### Added
- ...
### Changed
- ...
### Fixed
- ...
-->
