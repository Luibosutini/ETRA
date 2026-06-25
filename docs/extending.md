# 拡張ガイド

ETRA を初めて拡張する開発者向けの手順書です。関数・変数・API の一覧は [開発者リファレンス](./reference.md)、初回デプロイや日常運用は [運用手順](./operations.md) を参照してください。

## 開発環境セットアップ

Backend は Python 3.11 を前提にしています。`backend/pyproject.toml` は pytest、ruff、mypy の設定を持ち、`backend/requirements-dev.txt` に開発依存が定義されています。

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
pytest
ruff check .
mypy .
```

Portal は Vite + React です。`frontend/portal/package.json` に `dev`, `build`, `preview`, `lint` が定義されています。

```bash
cd frontend/portal
npm ci
npm run dev
npm run lint
npm run build
```

Terraform は dev 環境の `infra/terraform/envs/dev` から実行します。既存の state backend や初回構築手順は [運用手順](./operations.md#初回デプロイ手順) を確認してください。

```bash
cd infra/terraform/envs/dev
terraform init
terraform plan
```

解析ノード AMI は Packer で作ります。実行 script は `scripts/deploy/build_ami.sh` で、Packer template は `packer/etra-analysis.pkr.hcl`、変数は `packer/variables.pkr.hcl` です。

```bash
bash scripts/deploy/build_ami.sh
```

## 新しい Lambda 関数を追加する

1. `backend/lambda/<name>/<name>.py` を作成し、API Gateway 用なら `handler(event: dict, context: object) -> dict` 形式に揃える。認証が必要な API は `backend/shared/auth.py` の `get_caller_user_id()`, `get_caller_groups()`, `is_admin()` を使う。
2. HTTP response は既存 Lambda と同じ方針にする。通常 API は `backend/shared/response.py` を使い、既存の `admin_api` / `logs_api` のように局所 `_response()` を使う場合は CORS や status code の違いを明示的に判断する。
3. AWS client は `backend/shared/aws_clients.py` を優先する。新しい AWS service が必要なら shared に client factory を追加し、`REGION` の扱いを [開発者リファレンス](./reference.md#環境変数リファレンス) に追記する。
4. IAM を `infra/terraform/modules/iam/main.tf` に追加し、`outputs.tf` と `variables.tf` の呼び出し側に必要な値を増やす。
5. 通常の Lambda は `infra/terraform/modules/lambda/main.tf` の `local.functions` に追加し、`infra/terraform/modules/lambda/variables.tf` の `role_arns` object にも key を追加する。VPC 外に置く必要がある関数は `no_vpc_functions` へ追加する。
6. 環境変数は `infra/terraform/modules/lambda/main.tf` の `environment.variables` に追加する。運用者が変更する値なら `infra/terraform/envs/dev/variables.tf` に variable を追加し、`envs/dev/main.tf` から渡す。
7. Cognito trigger を追加する場合は、通常 Lambda module ではなく `infra/terraform/modules/cognito/main.tf` の trigger 定義と user pool `lambda_config` を更新する。
8. `backend/tests/test_<name>.py` を追加する。API event は `make_api_event(...)`、AWS service は moto または monkeypatch で置き換える。
9. `scripts/deploy/deploy_lambda.sh` は関数名取得と package/deploy 呼び出しを明示列挙しているため、新しい Lambda もこの script に追加する。

デプロイは infrastructure を反映してから Lambda code を更新します。

```bash
cd infra/terraform/envs/dev
terraform apply
cd ../../../../
bash scripts/deploy/deploy_lambda.sh
```

## 新しい API エンドポイントを追加する

1. エンドポイントを処理する Lambda を決める。新規 Lambda なら前節の手順で `modules/lambda` と `modules/iam` に登録する。
2. `infra/terraform/modules/apigateway/variables.tf` の `lambda_invoke_arns` と `lambda_function_names` object に必要な key を追加する。
3. `infra/terraform/modules/apigateway/main.tf` に `aws_apigatewayv2_integration`, `aws_apigatewayv2_route`, `aws_lambda_permission` を追加する。既存 route はすべて `authorization_type = "JWT"` と Cognito authorizer を使う。
4. admin 限定 API は API Gateway では group を制限せず、Lambda 内で `get_caller_groups()` または `is_admin()` により拒否する。
5. `infra/terraform/envs/dev/main.tf` の `module "apigateway"` に invoke ARN と function name を渡す。
6. `frontend/portal/src/api.ts` に client function と型を追加する。画面が必要なら `frontend/portal/src/pages/*.tsx` を追加し、`frontend/portal/src/App.tsx` の hash route と navigation に組み込む。
7. API のテストは Lambda handler 単位で追加し、必要なら frontend build と lint も確認する。

## 新しい Terraform module を追加する

1. `infra/terraform/modules/<name>/main.tf`, `variables.tf`, `outputs.tf` を作成する。既存 module と同じく `project` と `env` を受け取り、tag や name prefix を揃える。
2. `infra/terraform/envs/dev/main.tf` から `module "<name>"` を呼び出す。別 module の output に依存する場合は、呼び出し順ではなく参照で依存関係を表現する。
3. 運用者が設定する値は `infra/terraform/envs/dev/variables.tf` に追加する。default が無い variable は `terraform.tfvars` 側で必須になる。
4. 他の module へ渡す値がある場合は `outputs.tf` に出し、`envs/dev/main.tf` で接続する。
5. module の責務説明は [アーキテクチャ設計](./architecture.md#terraform-モジュール構成) に集約する。reference は変数や関数の表に留める。

## テストの追加方法

Backend test は `backend/tests` に置きます。`conftest.py` の `aws_env` は autouse で基本 env を設定しますが、module import 時に `os.environ[...]` を読む Lambda は import 前に必要 env を monkeypatch してください。

よく使う helper は次の通りです。

| helper | 使いどころ |
|---|---|
| `make_api_event(method, path, path_params, query_params, body, user_id, groups)` | API Gateway event と Cognito claims を作る。 |
| `workspace_bucket` | S3 workspace API のテスト用 bucket を作る。 |
| `stopped_instance` | EC2 start/stop/status 系のテスト用 instance を作る。 |
| `mock_aws()` | moto 対応 AWS service の client/resource をローカル mock にする。 |

追加後は backend で最低限 pytest を通します。

```bash
cd backend
pytest
ruff check .
mypy .
```

Frontend を触った場合は portal 側も確認します。

```bash
cd frontend/portal
npm run lint
npm run build
```

## 解析ノード AMI を拡張する

解析ノードに OS package、Python library、JupyterLab 設定、DCV 設定、systemd service、helper script を追加する場合は Packer scripts を編集します。

| ファイル | 拡張対象 |
|---|---|
| `packer/scripts/01-base-packages.sh` | Amazon Linux package、Python 3.11、開発 tool、`/etc/etra`。 |
| `packer/scripts/02-desktop-xfce.sh` | XFCE と DCV virtual session 用 `.xsession`。 |
| `packer/scripts/03-python-jupyter.sh` | JupyterLab、Python 解析 library、workspace directory。 |
| `packer/scripts/04-dcv-server.sh` | Amazon DCV server、web viewer、virtual session、QUIC 無効化。 |
| `packer/scripts/05-systemd-services.sh` | `jupyterlab.service`, `ws-sync-on-shutdown.service`, SSM agent。 |
| `packer/scripts/06-helper-scripts.sh` | `ws-sync-down`, `ws-sync-up`, `dcv-token`。 |
| `infra/terraform/modules/ec2/userdata.sh.tpl` | 起動時の `/etc/etra/config.env` 生成、SSM 診断、DCV/Jupyter 起動補正。 |

AMI build 後は出力された AMI ID を `infra/terraform/envs/dev/terraform.tfvars` の `ami_id` に設定し、Terraform を apply します。

## デプロイ手順への導線

実際の deploy script は `scripts/deploy` 配下にあります。

| script | 役割 |
|---|---|
| `scripts/deploy/build_ami.sh` | Terraform output から public subnet を取得し、Packer で解析ノード AMI を build する。 |
| `scripts/deploy/deploy_lambda.sh` | Terraform output から Lambda function name を取得し、backend Lambda を zip 化して `aws lambda update-function-code` する。 |
| `scripts/deploy/deploy_portal.sh` | portal の `public/config.js` を生成し、`npm ci`, `npm run build` 後に S3 へ upload する。 |
| `scripts/deploy/deploy_ohif.sh` | OHIF config を生成し、build artifact を S3 `/ohif/` へ upload する。 |

手順全体と確認項目は [運用手順](./operations.md) にまとめる方針です。拡張で script の前提や順序が変わる場合は、実装変更とあわせて operations 側の更新も検討してください。
