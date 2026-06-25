# 用語集

ETRA 固有概念を、保守や拡張で参照する実装場所とあわせて定義する用語集です。全体構成は [アーキテクチャ設計](./architecture.md)、関数・変数の詳細は [開発者リファレンス](./reference.md) を参照してください。

## ワークスペース

| 用語 | 定義 | 関連する実装場所 |
|---|---|---|
| workspace | 利用者ごとの解析入力・共有資料・結果を格納する S3 ベースの作業領域。ポータルは S3 key prefix を切り替えて一覧、アップロード、ダウンロード、削除を行う。 | `backend/lambda/workspace_api/workspace_api.py`, `frontend/portal/src/pages/WorkspacePage.tsx`, `infra/terraform/modules/s3/main.tf` |
| `personal/<uid>/` | Cognito user `sub` ごとの個人領域。`assert_workspace_access()` が `uid` と呼び出し元ユーザーを照合し、本人以外のアクセスを拒否する。 | `backend/shared/auth.py`, `backend/lambda/workspace_api/workspace_api.py` |
| `shared/dropbox/` | 全ユーザーがアクセスできる共有 dropbox。S3 lifecycle rule `dropbox-ttl-24h` により 1 日で current version と noncurrent version を削除する。 | `infra/terraform/modules/s3/main.tf`, `frontend/portal/src/pages/WorkspacePage.tsx` |
| `shared/templates/` | 全ユーザーが参照できるテンプレート置き場。ワークスペース API では `shared/` 配下として許可され、ポータルでは `Shared / Templates` として表示される。 | `backend/shared/auth.py`, `frontend/portal/src/pages/WorkspacePage.tsx` |
| `results/<uid>/` | 解析結果をユーザーごとに格納する領域。`personal/<uid>/` と同じく本人の `uid` のみアクセスできる。 | `backend/shared/auth.py`, `frontend/portal/src/pages/WorkspacePage.tsx` |
| presigned URL | S3 object への一時的な GET/PUT URL。`workspace_api` は download/upload 用に 900 秒有効の URL を発行する。 | `backend/lambda/workspace_api/workspace_api.py`, `frontend/portal/src/api.ts` |

## 解析ノード・アクセス

| 用語 | 定義 | 関連する実装場所 |
|---|---|---|
| compute node | ユーザーが JupyterLab、DCV、解析ライブラリを使う EC2 解析ノード。`start_compute` が既存の stopped node を再起動し、無ければ Launch Template から作成する。 | `backend/lambda/start_compute/start_compute.py`, `infra/terraform/modules/ec2/main.tf`, `packer/etra-analysis.pkr.hcl` |
| Launch Template | 解析ノードの AMI、subnet、security group、instance profile、userdata をまとめた EC2 起動テンプレート。Lambda は `LAUNCH_TEMPLATE_ID` を使って新規 node を作成する。 | `infra/terraform/modules/ec2/main.tf`, `backend/lambda/start_compute/start_compute.py` |
| Owner tag | EC2 instance と volume に付けるユーザー識別タグ。一般ユーザーは `Owner=<sub>` の node だけを stop/status/restart でき、admin は全台を対象にできる処理がある。 | `backend/lambda/start_compute/start_compute.py`, `backend/lambda/stop_compute/stop_compute.py`, `backend/lambda/status_compute/status_compute.py`, `backend/lambda/restart_jupyter/restart_jupyter.py` |
| instance-id | EC2 instance の実体 ID。ポータルからの stop/restart/terminate や status query の対象指定に使う。 | `frontend/portal/src/api.ts`, `backend/lambda/stop_compute/stop_compute.py`, `backend/lambda/status_compute/status_compute.py`, `backend/lambda/admin_api/admin_api.py` |
| SSM port forwarding | AWS Systems Manager Session Manager を使い、JupyterLab `8888` や DCV `8443` を localhost に転送する接続方式。ポータルは一時認証情報入りの `.bat` / `.sh` を生成する。 | `backend/lambda/connect_api/connect_api.py`, `frontend/portal/src/pages/ConnectPage.tsx` |
| DCV token | Amazon DCV 接続用の一時認証情報。現在の実装は `restart_jupyter` の `/connect/dcv-token` 処理で `ec2-user` の一時 password を SSM Run Command で設定する。 | `backend/lambda/restart_jupyter/restart_jupyter.py`, `frontend/portal/src/pages/ConnectPage.tsx`, `packer/scripts/04-dcv-server.sh` |
| JupyterLab | 解析ノード上で動く notebook 環境。AMI build 時にインストールされ、`jupyterlab.service` として起動する。 | `packer/scripts/03-python-jupyter.sh`, `packer/scripts/05-systemd-services.sh`, `backend/lambda/restart_jupyter/restart_jupyter.py` |

## 認証・認可

| 用語 | 定義 | 関連する実装場所 |
|---|---|---|
| Cognito `admin` group | 管理機能を使える Cognito group。admin API、logs API、admin 向け instance 操作では Lambda 内で group を確認する。 | `infra/terraform/modules/cognito/main.tf`, `backend/shared/auth.py`, `backend/lambda/admin_api/admin_api.py`, `backend/lambda/logs_api/logs_api.py` |
| Cognito `user` group | 一般利用者 group。Post-confirmation trigger がメール確認済みユーザーを自動追加する。 | `infra/terraform/modules/cognito/main.tf`, `backend/lambda/cognito_post_confirmation/cognito_post_confirmation.py` |
| JWT Authorizer | API Gateway HTTP API の JWT authorizer。Cognito user pool client を audience、user pool を issuer として Bearer token を検証する。 | `infra/terraform/modules/apigateway/main.tf`, `frontend/portal/src/auth.ts` |
| Cognito Pre-signup trigger | サインアップ前に email domain と optional allowlist を検証し、不許可なら例外で登録を拒否する Lambda trigger。 | `backend/lambda/cognito_pre_signup/cognito_pre_signup.py`, `infra/terraform/modules/cognito/main.tf` |
| Cognito Post-confirmation trigger | メール確認完了後にユーザーを `user` group へ追加する Lambda trigger。Cognito の期待どおり event をそのまま返す。 | `backend/lambda/cognito_post_confirmation/cognito_post_confirmation.py`, `infra/terraform/modules/cognito/main.tf` |

## DICOM

| 用語 | 定義 | 関連する実装場所 |
|---|---|---|
| HealthImaging datastore | AWS HealthImaging の DICOM 保管先。`dicom_api` は `DATASTORE_ID` を使って ImageSet を検索する。 | `infra/terraform/modules/healthimaging/main.tf`, `backend/lambda/dicom_api/dicom_api.py` |
| ImageSet | HealthImaging の検索結果単位。`_to_study()` が ImageSet summary の DICOM tags をポータル用の study 表示形式へ変換する。 | `backend/lambda/dicom_api/dicom_api.py`, `frontend/portal/src/api.ts` |
| OHIF Viewer | DICOM study を閲覧する viewer。ポータルは `StudyInstanceUIDs` を付けて `/ohif/viewer` を開く。 | `frontend/portal/src/pages/DicomPage.tsx`, `scripts/deploy/deploy_ohif.sh` |

## 運用自動化

| 用語 | 定義 | 関連する実装場所 |
|---|---|---|
| CPU アイドル検知 | 実行中 EC2 の平均 CPU が閾値未満の場合に停止する cleanup 処理。`IDLE_CPU_THRESHOLD` と `IDLE_DURATION_MINUTES` で判定する。 | `backend/lambda/cleanup_compute/cleanup_compute.py`, `infra/terraform/modules/eventbridge/main.tf` |
| EventBridge Scheduler | `cleanup_compute` を 15 分ごとに起動する scheduler。定期 cleanup の起点になる。 | `infra/terraform/modules/eventbridge/main.tf` |
| state transition | EC2 の状態遷移。`cleanup_compute` は `StateTransitionReason` から停止時刻を読み、長期停止 node を terminate する。 | `backend/lambda/cleanup_compute/cleanup_compute.py` |
| EC2 状態通知 | EC2 state-change event を受け、`running` / `stopped` / `terminated` を SNS に通知する処理。 | `backend/lambda/notify_status/notify_status.py`, `infra/terraform/modules/cloudwatch/main.tf` |
| workspace sync | 解析ノードの `/home/ec2-user/workspace/personal` と S3 `personal/<Owner>/` を同期する helper。起動時 sync-down と停止前 sync-up がある。 | `packer/scripts/05-systemd-services.sh`, `packer/scripts/06-helper-scripts.sh`, `infra/terraform/modules/ec2/userdata.sh.tpl` |
