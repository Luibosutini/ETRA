# CLAUDE.md

## プロジェクト概要
本プロジェクトは **ETRA**（医用画像解析基盤）であり、AWS 上に構築する。DICOM 画像の正式保管・閲覧と、MATLAB / Python による解析実行環境を統合的に提供する。
構成はハイブリッド型とし、DICOM の正式保管・閲覧は AWS HealthImaging + OHIF Viewer、頻繁な解析処理は EC2 ベースのオンデマンド実行環境と S3 系ワークスペースで処理する。

> このファイルは変更ログとして使用しない。変更履歴はCHANGELOG.mdに記録すること。 
---

## 技術スタック

### Cloud / Infrastructure
- AWS
- Amazon VPC
- AWS HealthImaging
- Amazon S3
- Amazon EC2
- Amazon EBS
- Amazon DCV
- AWS Lambda
- AWS Systems Manager
- Amazon EventBridge
- Amazon CloudWatch
- AWS CloudTrail
- Amazon Cognito
- Amazon Q Developer in chat applications

### Frontend
- OHIF Viewer 3.x
- Node.js 20.x
- npm 10.x

### Backend / Automation
- Python 3.11
- boto3 1.x
- AWS Lambda Python 3.11 runtime

### Analysis Environment
- MATLAB R2024b（暫定。導入版に合わせて固定すること）
- Python 3.11
- JupyterLab 4.x
- NumPy 2.x
- SciPy 1.13+
- pandas 2.x
- matplotlib 3.8+

### Infrastructure as Code
- Terraform 1.8+（暫定）

### Optional
- Amazon EFS
- Amazon FSx for Lustre

---

## 採用方針
- DICOM の正式保管・閲覧は HealthImaging を中核にする。
- 頻繁な解析アクセスは HealthImaging に直接集中させず、S3 系ワークスペースへ分離する。
- MATLAB GUI を伴う既存資産は EC2 + Amazon DCV を前提に扱う。
- 高コストな解析ノードは常時起動ではなく、オンデマンド起動を前提とする。
- 利用者の主要操作は、可能な限りアプリケーション内で完結できるように設計する。
- 1か月の運用後にコストとアクセス傾向を観測し、ストレージと計算基盤の再設計を判断する。

---

## 非採用方針
- DICOM 正式保管を S3 単独で置き換えない。
- HealthImaging を解析用の主ストレージとして扱わない。
- GUI を必要とする MATLAB 実行を Lambda / Fargate 前提で設計しない。
- 高額な EC2 を常時起動前提で設計しない。
- 一時共有領域を恒久保管領域として設計しない。

---

## コマンド一覧

### Frontend
```bash
cd frontend/ohif
npm install
npm run dev
npm run build
npm run lint
```

### Backend
```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pytest
ruff check .
mypy .
```

### Infrastructure
```bash
cd infra/terraform
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

### Utility / AWS CLI
```bash
aws s3 ls
aws healthimaging list-datastores
aws ec2 describe-instances
aws ssm start-automation-execution
aws logs tail /aws/lambda/<function-name> --follow
```

### Analysis
```bash
jupyter lab
python analysis/python/scripts/run_analysis.py
```

---

## ディレクトリ構造
```text
project-root/
├─ CLAUDE.md
├─ README.md
├─ docs/
│  ├─ architecture.md
│  ├─ requirements.md
│  ├─ operations.md
│  └─ security.md
├─ frontend/
│  └─ ohif/
├─ backend/
│  ├─ lambda/
│  │  ├─ start_compute/
│  │  ├─ stop_compute/
│  │  ├─ status_compute/
│  │  ├─ workspace_api/
│  │  └─ notify_status/
│  ├─ shared/
│  └─ tests/
├─ infra/
│  └─ terraform/
│     ├─ envs/
│     ├─ modules/
│     └─ global/
├─ analysis/
│  ├─ matlab/
│  ├─ python/
│  ├─ notebooks/
│  └─ containers/
├─ scripts/
│  ├─ bootstrap/
│  ├─ deploy/
│  └─ ops/
├─ config/
│  ├─ dev/
│  ├─ stg/
│  └─ prod/
└─ .github/
   └─ workflows/
```

### 責務
- `frontend/ohif`: DICOM 閲覧 UI
- `backend/lambda`: 起動停止、状態照会、ワークスペース API、通知
- `infra/terraform`: AWS リソース定義
- `analysis/matlab`: MATLAB スクリプト、GUI 資産、テンプレート
- `analysis/python`: Python 解析コード
- `docs`: 人間向け設計資料
- `scripts/ops`: 運用補助スクリプト

---

## ワークスペース方針
ワークスペースは論理的に以下へ分離すること。

- `personal/`: 各利用者の主作業領域
- `shared/dropbox/`: 一時共有領域。配置後 24 時間で自動削除
- `shared/templates/`: 正式共有テンプレート領域
- `results/`: 実行結果保存領域

### ワークスペース原則
- 個人作業は `personal/` を主領域とする。
- 一時受け渡しは `shared/dropbox/` を使用する。
- 再利用前提の設定ファイルやテンプレートは `shared/templates/` で管理する。
- 実行結果は `results/` に保存し、入力や設定と混在させない。
- `shared/dropbox/` を恒久保管に使ってはならない。

---

## 推奨事項
1. DICOM の正式保管と解析用ワーク領域を分離する。
2. 高コストな解析ノードはオンデマンド起動を基本とする。
3. マネージドサービスを優先する。
4. GUI 要件を前提に MATLAB 実行基盤を選定する。
5. 小さく導入し、1か月運用後にコスト再評価を行う。
6. 機能より先に責務境界を守る。
7. 監査可能な操作だけを正式機能とする。
8. 利用者の主要操作はアプリケーション内で完結できることを優先する。
9. 共有フォルダと個人フォルダを明確に分離する。
10. 設定ファイルはコードと同等に管理対象とする。
11. コード編集 → 設定選択 → 実行 → 結果確認の導線を短く保つ。

---

## 禁止事項
1. HealthImaging を解析用の主ストレージとして扱わない。
2. 高額な EC2 を常時起動前提で設計しない。
3. MATLAB GUI 前提の処理を Lambda / Fargate に載せない。
4. DICOM 正式保管を S3 単独で代替した前提で設計しない。
5. 本番用 IAM 権限を広く取りすぎない。
6. 一時コードや検証コードを本番ディレクトリに混在させない。
7. 起動・停止・アクセスの監査ログが取れない仕組みを正式採用しない。
8. ユーザーが直接 EC2 を自由起動できる構成にしない。
9. 解析結果と原本 DICOM を同じ責務の保存先に混在させない。
10. 未確定要件を勝手に重機能化しない。
11. コード編集を完全に外部環境依存にしない。
12. 共有設定ファイルを手動配布前提にしない。
13. 個人領域と共有領域を混在させない。
14. `shared/dropbox/` を恒久保管領域として扱わない。
15. 正式テンプレートを一時共有領域で配布し続けない。

---

## 行動原則
1. **役割分離を厳守する**  
   DICOM 正式保管・閲覧、解析実行、運用自動化、監査ログは別責務として扱うこと。

2. **HealthImaging を解析主ストレージとして扱わない**  
   解析用データは S3 / EFS / FSx 側へ分離すること。

3. **常時起動前提で設計しない**  
   解析ノードは停止可能性・再起動可能性を前提に設計すること。

4. **GUI 利用要件を無視しない**  
   GUI が必要な MATLAB 資産は EC2 + DCV 前提で判断すること。

5. **マネージドサービス優先**  
   認証、監査、スケジューリング、起動停止制御は AWS マネージドサービスを優先すること。

6. **監査可能性を損なわない**  
   起動停止、画像アクセス、解析開始、結果保存などの主要操作は追跡可能にすること。

7. **小さく変更する**  
   変更は小さい単位に分け、影響範囲を明示すること。

8. **推測で補完しすぎない**  
   未確定要件は勝手に別サービスへ置き換えず、現行方針の範囲で最小実装を提案すること。

9. **セキュリティを後回しにしない**  
   IAM、Secrets、ネットワーク露出、暗号化を初期設計に含めること。

10. **人間が運用できる形を優先する**  
   理論上の最適解よりも、少人数チームが継続運用できる構成を優先すること。

---

## 機能優先度

### 初期リリースで必須
- DICOM の保管と閲覧
- アプリ内コード編集
- 設定ファイルのインポート / エクスポート
- `personal/` と `shared/dropbox/` と `shared/templates/` の分離
- MATLAB ノードの起動 / 停止 / 状態確認
- Python 実行環境
- 実行結果の保存
- 管理者 / 一般利用者レベルの権限分離
- 基本監査ログ

### 初期は簡易でもよい
- 単一ファイル編集
- 共有テンプレート参照
- 実行ログ表示
- 状態通知

### 後回しでよい
- 高度な共同編集
- GPU 自動選択
- 複数計算ノードの自動振り分け
- 高度な検索 UI
- 解析パイプライン全自動化
- 複雑な承認フロー

---

## 実装時チェックリスト
変更提案時は必ず以下を確認すること。
- コスト影響があるか
- IAM 変更があるか
- 監査ログに影響するか
- 停止 / 再起動で壊れないか
- GUI 要件に影響するか
- ワークスペース責務を壊していないか
- `shared/dropbox/` の 24 時間削除方針と矛盾しないか

## 参考ドキュメント

- 詳細なアーキテクチャ: [docs/architecture.md](docs/architecture.md)
- 要件定義: [docs/requirements.md](docs/requirements.md)
- 運用手順: [docs/operations.md](docs/operations.md)
- セキュリティ設計: [docs/security.md](docs/security.md)
- 変更履歴: [CHANGELOG.md](CHANGELOG.md)
- タスク管理: [todo.md](todo.md)
