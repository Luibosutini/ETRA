# 開発者リファレンス

ETRA の関数、変数、API、設定を実装ファイルに沿って引くためのリファレンスです。全体構成、ネットワーク、Terraform module の責務は [アーキテクチャ設計](./architecture.md) に委譲します。

## Backend: Lambda 関数

| 関数 | ファイル | handler | 責務 | 主要 env | 主要内部関数 |
|---|---|---|---|---|---|
| `start_compute` | `backend/lambda/start_compute/start_compute.py` | `handler(event: dict, context: object) -> dict` | 呼び出しユーザーの EC2 解析ノードを起動する。既存 node が `running` / `pending` / `stopping` / `stopped` なら状態に応じて返却または start し、無ければ Launch Template から作成する。 | `REGION`, `LAUNCH_TEMPLATE_ID`, `ANALYSIS_INSTANCE_TAG_KEY`, `ANALYSIS_INSTANCE_TAG_VALUE` | `_find_user_instance()` |
| `stop_compute` | `backend/lambda/stop_compute/stop_compute.py` | `handler(event: dict, context: object) -> dict` | EC2 解析ノードを停止する。admin は project tag 配下の全台、一般ユーザーは `Owner` tag が本人の node のみ対象。 | `REGION`, `ANALYSIS_INSTANCE_TAG_KEY`, `ANALYSIS_INSTANCE_TAG_VALUE` | - |
| `status_compute` | `backend/lambda/status_compute/status_compute.py` | `handler(event: dict, context: object) -> dict` | EC2 解析ノードの状態一覧または指定 `instance_id` の状態を返す。running node は SSM 接続状態も付与する。 | `REGION`, `ANALYSIS_INSTANCE_TAG_KEY`, `ANALYSIS_INSTANCE_TAG_VALUE` | `_instance_summary()`, `_get_ssm_connected_ids()` |
| `workspace_api` | `backend/lambda/workspace_api/workspace_api.py` | `handler(event: dict, context: object) -> dict` | S3 workspace の一覧、download URL、upload URL、削除を扱う。`personal/<uid>/`, `results/<uid>/`, `shared/` の認可を行う。 | `REGION`, `WORKSPACE_BUCKET` | `_list_objects()` |
| `notify_status` | `backend/lambda/notify_status/notify_status.py` | `handler(event: dict, context: object) -> dict` | EventBridge の EC2 state-change event を受け、`running` / `stopped` / `terminated` を SNS に通知する。 | `REGION`, `NOTIFICATION_TOPIC_ARN` | - |
| `dicom_api` | `backend/lambda/dicom_api/dicom_api.py` | `handler(event: dict, context: object) -> dict` | HealthImaging ImageSet を検索し、study 一覧、pagination、`patient_id` filter を提供する。 | `REGION`, `DATASTORE_ID` | `_to_study()` |
| `admin_api` | `backend/lambda/admin_api/admin_api.py` | `handler(event: dict, _context) -> dict` | admin 限定で Cognito user/group 管理と EC2 terminate を行う。 | `USER_POOL_ID` | `_list_users()`, `_add_user_to_group()`, `_remove_user_from_group()`, `_terminate_instance()` |
| `logs_api` | `backend/lambda/logs_api/logs_api.py` | `handler(event: dict, _context) -> dict` | admin 限定で CloudWatch Logs の log group 一覧と直近 24 時間の log event を返す。 | `LOG_GROUP_PREFIX` | `_list_log_groups()`, `_get_log_events()` |
| `cleanup_compute` | `backend/lambda/cleanup_compute/cleanup_compute.py` | `handler(event: dict, context: object) -> dict` | EventBridge Scheduler から定期実行され、CPU idle node を stop し、長期 stopped node を terminate する。 | `REGION`, `ANALYSIS_INSTANCE_TAG_KEY`, `ANALYSIS_INSTANCE_TAG_VALUE`, `IDLE_CPU_THRESHOLD`, `IDLE_DURATION_MINUTES`, `STOPPED_DAYS_THRESHOLD` | `_get_avg_cpu()`, `_parse_state_transition_time()` |
| `connect_api` | `backend/lambda/connect_api/connect_api.py` | `handler(event: dict, context) -> dict` | `/connect/credentials` 用に STS `assume_role` を行い、SSM port forwarding 用の一時 credential を返す。 | `SSM_CONNECT_ROLE_ARN`, `REGION` | `_resp()` |
| `restart_jupyter` | `backend/lambda/restart_jupyter/restart_jupyter.py` | `handler(event: dict, context) -> dict` | `/compute/restart-jupyter` では SSM Run Command で JupyterLab を修復・再起動し、`/connect/dcv-token` では DCV 用一時 password を生成する。 | `REGION`, `ANALYSIS_INSTANCE_TAG_KEY`, `ANALYSIS_INSTANCE_TAG_VALUE` | `_handle_dcv_token()`, `_resp()` |
| `cognito_post_confirmation` | `backend/lambda/cognito_post_confirmation/cognito_post_confirmation.py` | `handler(event: dict, context: object) -> dict` | Cognito PostConfirmation で、確認完了ユーザーを `user` group へ自動追加する。 | `AWS_REGION`, `USER_POOL_ID` | - |
| `cognito_pre_signup` | `backend/lambda/cognito_pre_signup/cognito_pre_signup.py` | `handler(event: dict, context: object) -> dict` | Cognito PreSignup で、許可 email domain と optional allowlist を検証する。 | `ALLOWED_EMAIL_DOMAINS`, `ALLOWED_EMAILS` | `_allowed_domains()`, `_allowed_emails()` |

## shared モジュール

| モジュール | ファイル | 関数 | 役割 |
|---|---|---|---|
| `aws_clients` | `backend/shared/aws_clients.py` | `ec2_client()`, `s3_client()`, `sns_client()`, `cloudwatch_client()`, `medical_imaging_client()` | `os.environ["REGION"]` を使って boto3 client を生成する。 |
| `auth` | `backend/shared/auth.py` | `_decode_jwt_payload(token: str) -> dict[str, Any]`, `_get_claims(event: dict) -> dict` | JWT payload decode と API Gateway v1/v2 の claims 取得。署名検証は API Gateway Cognito authorizer 側に委ねる設計。 |
| `auth` | `backend/shared/auth.py` | `get_caller_user_id(event: dict) -> str`, `get_caller_groups(event: dict) -> list[str]`, `is_admin(event: dict) -> bool` | Cognito `sub` と `cognito:groups` を取り出す。group は list、JSON array string、space/comma 区切りを扱う。 |
| `auth` | `backend/shared/auth.py` | `assert_workspace_access(user_id: str, s3_key: str) -> None` | `personal/<uid>/`, `results/<uid>/`, `shared/` の workspace access rule を検証し、違反時は `PermissionError` を投げる。 |
| `response` | `backend/shared/response.py` | `ok(body)`, `bad_request(message)`, `forbidden(message="Forbidden")`, `not_found(message="Not found")`, `server_error(message="Internal server error")` | API Gateway response dict を生成する。CORS は `Access-Control-Allow-Origin: *`。 |

## API エンドポイント

| method | path | 機能 | frontend client | Lambda | 認可 |
|---|---|---|---|---|---|
| GET | `/compute/status` | instance 一覧と状態、SSM 接続状態 | `getComputeStatus()` | `status_compute` | 認証 |
| POST | `/compute/start` | 解析ノード起動。body の `instance_id` は任意 | `startCompute(instanceId?)` | `start_compute` | 認証 |
| POST | `/compute/stop` | 解析ノード停止。body の `instance_id` は任意 | `stopCompute(instanceId?)` | `stop_compute` | 認証 |
| POST | `/compute/restart-jupyter` | JupyterLab 再起動。body の `instance_id` は任意 | `restartJupyter(instanceId?)` | `restart_jupyter` | 認証 |
| GET | `/workspace` | workspace file 一覧。query `prefix` | `listWorkspace(prefix)` | `workspace_api` | 認証 |
| GET | `/workspace/{proxy+}` | download presigned URL 発行 | `getDownloadUrl(key)` | `workspace_api` | 認証 |
| PUT | `/workspace/{proxy+}` | upload presigned URL 発行。query `content_type` | `getUploadUrl(key, contentType)` | `workspace_api` | 認証 |
| DELETE | `/workspace/{proxy+}` | S3 object 削除 | `deleteWorkspaceItem(key)` | `workspace_api` | 認証 |
| GET | `/admin/users` | Cognito user 一覧 | `listUsers()` | `admin_api` | admin |
| POST | `/admin/users/{username}/groups/{group}` | Cognito group 追加 | `addUserToGroup(username, group)` | `admin_api` | admin |
| DELETE | `/admin/users/{username}/groups/{group}` | Cognito group 削除 | `removeUserFromGroup(username, group)` | `admin_api` | admin |
| POST | `/admin/instances/{instance_id}/terminate` | EC2 terminate | `terminateInstance(instanceId)` | `admin_api` | admin |
| GET | `/connect/credentials` | SSM port forwarding 用一時 credential | `getConnectCredentials()` | `connect_api` | 認証 |
| GET | `/connect/dcv-token` | DCV 接続用一時 password | `getDcvToken()` | `restart_jupyter` | 認証 |
| GET | `/dicom/studies` | HealthImaging study 一覧。query `max_results`, `next_token`, `patient_id` | `listDicomStudies({ nextToken?, patientId? })` | `dicom_api` | 認証 |
| GET | `/logs` | CloudWatch log group 一覧 | `listLogGroups()` | `logs_api` | admin |
| GET | `/logs/events` | log event 取得。query `group`, `limit` | `getLogEvents(group, limit)` | `logs_api` | admin |

## frontend/portal 構成

| ファイル | 役割 |
|---|---|
| `frontend/portal/src/App.tsx` | Cognito callback 処理、認証状態初期化、silent renew error 時の再ログイン、hash routing。route は `#dashboard`, `#workspace`, `#dicom`, `#connect`, `#admin`, `#logs`。 |
| `frontend/portal/src/api.ts` | `apiFetch()` で Bearer token を自動付与し、compute/workspace/admin/connect/DICOM/logs の client function を提供する。 |
| `frontend/portal/src/auth.ts` | `oidc-client-ts` の `UserManager` を生成し、`getUser`, `getAccessToken`, `isAdmin`, `signIn`, `signOut`, `handleCallback`, `onSilentRenewError` を提供する。 |
| `frontend/portal/src/config.ts` | `window.__ETRA_CONFIG__` から API endpoint、Cognito authority、Hosted UI domain、client id、redirect/logout URI、region を読む。 |
| `frontend/portal/src/main.tsx` | React entrypoint。 |
| `frontend/portal/src/index.css` | Tailwind を含む portal の global style。 |
| `frontend/portal/src/pages/DashboardPage.tsx` | 解析ノードの status/start/stop/restart/terminate 操作。terminate は admin のみ表示。 |
| `frontend/portal/src/pages/WorkspacePage.tsx` | workspace prefix 切替、S3 一覧、upload/download/delete、編集 modal 起動。 |
| `frontend/portal/src/pages/CodeEditorModal.tsx` | 1 MB 以下の text/code file を presigned URL 経由で読み書きする CodeMirror modal。 |
| `frontend/portal/src/pages/DicomPage.tsx` | HealthImaging study 一覧、`patient_id` 完全一致検索、pagination、OHIF viewer 起動。 |
| `frontend/portal/src/pages/ConnectPage.tsx` | SSM port forwarding 用 `.bat` / `.sh` と DCV 接続情報を生成する。 |
| `frontend/portal/src/pages/AdminPage.tsx` | admin 限定の Cognito user/group 管理。 |
| `frontend/portal/src/pages/LogsPage.tsx` | admin 限定の CloudWatch Logs group/event 参照。 |

## 環境変数リファレンス

| 変数 | 対象 Lambda | コード上の default | 説明 |
|---|---|---|---|
| `REGION` | `start_compute`, `stop_compute`, `status_compute`, `workspace_api`, `notify_status`, `dicom_api`, `cleanup_compute`, `connect_api`, `restart_jupyter` | shared client 経由は default なし。`connect_api` と `restart_jupyter` は `"us-east-1"`。`notify_status` の event message fallback は `""`。 | boto3 client の region。`infra/terraform/modules/lambda/main.tf` は `var.region` を注入する。 |
| `AWS_REGION` | `cognito_post_confirmation` | `"us-east-1"` | Cognito IDP client の region fallback。 |
| `LAUNCH_TEMPLATE_ID` | `start_compute` | `""` | EC2 Launch Template ID。未設定で新規作成が必要な場合は server error。 |
| `ANALYSIS_INSTANCE_TAG_KEY` | `start_compute`, `stop_compute`, `status_compute`, `cleanup_compute`, `restart_jupyter` | `"Project"` | 対象 EC2 を絞り込む tag key。 |
| `ANALYSIS_INSTANCE_TAG_VALUE` | `start_compute`, `stop_compute`, `status_compute`, `cleanup_compute`, `restart_jupyter` | `start/stop/status/cleanup` は `""`、`restart_jupyter` は `"etra"` | 対象 EC2 を絞り込む tag value。Terraform は通常 `var.project` を注入する。 |
| `WORKSPACE_BUCKET` | `workspace_api` | default なし | workspace S3 bucket name。`os.environ["WORKSPACE_BUCKET"]` で必須参照。 |
| `NOTIFICATION_TOPIC_ARN` | `notify_status` | `""` | EC2 状態通知の SNS topic ARN。空なら publish を skip。 |
| `DATASTORE_ID` | `dicom_api` | default なし | HealthImaging datastore ID。`os.environ["DATASTORE_ID"]` で必須参照。 |
| `USER_POOL_ID` | `admin_api`, `cognito_post_confirmation` | `admin_api` は default なし。`cognito_post_confirmation` は `""`。 | Cognito user pool ID。PostConfirmation は `event.userPoolId` を優先する。 |
| `SSM_CONNECT_ROLE_ARN` | `connect_api` | default なし | SSM port forwarding 用一時 credential を発行するために assume する IAM role ARN。 |
| `IDLE_CPU_THRESHOLD` | `cleanup_compute` | `"5.0"` | idle とみなす CPU 使用率の閾値。 |
| `IDLE_DURATION_MINUTES` | `cleanup_compute` | `"30"` | CPU 平均値を見る期間。Terraform の現在値は `"120"`。 |
| `STOPPED_DAYS_THRESHOLD` | `cleanup_compute` | `"7"` | stopped node を terminate するまでの日数。 |
| `LOG_GROUP_PREFIX` | `logs_api` | `"/aws/lambda/"` | log group 一覧を絞り込む prefix。Terraform の現在値は `/aws/lambda/${var.project}-${var.env}-`。 |
| `ALLOWED_EMAIL_DOMAINS` | `cognito_pre_signup` | `""` | 許可する email domain の comma-separated list。空なら登録拒否。 |
| `ALLOWED_EMAILS` | `cognito_pre_signup` | `""` | optional email allowlist。空なら domain check のみ。 |

## Terraform variables

`infra/terraform/envs/dev/variables.tf` に実在する変数のみを記載します。

| 変数 | 型 | default | 説明 |
|---|---|---|---|
| `project` | `string` | `"etra"` | Project tag と名前 prefix。 |
| `env` | `string` | `"dev"` | Environment tag と名前 prefix。 |
| `region` | `string` | `"us-east-1"` | AWS provider region。 |
| `ec2_instance_type` | `string` | `"t3.xlarge"` | 解析ノードの EC2 instance type。 |
| `ami_id` | `string` | default なし | Packer で作成した ETRA custom AMI ID。 |
| `allowed_email_domains` | `list(string)` | default なし | Cognito signup を許可する email domain。 |
| `allowed_emails` | `list(string)` | `[]` | Cognito signup を許可する email address allowlist。 |
| `cognito_callback_urls` | `list(string)` | `["https://localhost:3000/callback"]` | Cognito user pool client callback URLs。 |
| `cognito_logout_urls` | `list(string)` | `["https://localhost:3000/logout"]` | Cognito user pool client logout URLs。 |
| `alert_emails` | `list(string)` | `[]` | CloudWatch alarm と Budgets の通知先 email。 |
| `monthly_budget_usd` | `string` | `"100"` | 月間 budget 上限 USD。 |

## Terraform modules

dev 環境は `infra/terraform/envs/dev/main.tf` で `vpc`, `s3`, `iam`, `cognito`, `healthimaging`, `ec2`, `lambda`, `eventbridge`, `cloudtrail`, `cloudwatch`, `apigateway`, `cloudfront` の 12 module を呼び出します。各 module の責務説明は [アーキテクチャ設計: Terraform モジュール構成](./architecture.md#terraform-モジュール構成) を参照してください。

## テスト

`backend/tests/conftest.py` の主要 fixture は次の通りです。

| fixture / helper | 役割 |
|---|---|
| `aws_env` | autouse fixture。`REGION`, AWS dummy credentials, tag env, `WORKSPACE_BUCKET`, `DATASTORE_ID` などを設定する。 |
| `stopped_instance` | moto で stopped EC2 instance を作り、instance ID を返す。 |
| `workspace_bucket` | moto で `test-workspace` S3 bucket を作る。 |
| `make_api_event(...)` | API Gateway v1 風 event を作る。`sub` と comma-separated `cognito:groups` を claims に入れる。 |

Backend test は moto と pytest で実行します。

```bash
cd backend
pytest
ruff check .
mypy .
```
