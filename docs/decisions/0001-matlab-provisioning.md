# 0001 — MATLAB 解析ノードへの導入方式

## Context
ETRA 解析ノード AMI に MATLAB 本体が未導入（packer 01–06 は base/XFCE/Python・Jupyter/DCV/systemd/helper のみ）。
ライセンスは確定済み（architecture.md）: 東海大 Campus-Wide **Individual**、実行時に各ユーザーが MathWorks アカウントで対話認証、ライセンスサーバー不要、全製品利用可。
よってライセンスは実行時に解決済みで、決めるべきは「MATLAB ソフトウェアの導入場所と方法」。
基準: 再現性 / ノード起動の速さ / 更新容易性 / CLAUDE.md 適合（小さく・マネージド・EFS 後回し）/ コスト。

## Options considered
- **A. Packer ビルド時に mpm で AMI へ焼き込み**（R2024b + 厳選製品を /opt/matlab、`matlab` を PATH）。実行時に各自 MathWorks 認証。
- **C. 別 EBS/EFS に置き実行時マウント**（AMI 軽量・更新一元化だが運用増、EFS は方針上後回し）。
- **D. 初回起動時に userdata で mpm 実行**（AMI 最小だが起動最遅・NAT 課金・失敗で起動不能）。

## Decision
**A を採用**。既存のイミュータブル AMI 方針（01–06 が DCV/Jupyter を焼き込み）に一致し、オンデマンド起動モデルで最重要の「起動＝即利用可」を最速・再現性高く・ネット非依存で満たす。
製品は全部入れず `mpm --products` を `variables.pkr.hcl` でパラメータ化し厳選。リリースは R2024b を pin。
決め手: C の更新一元化の利点は、EFS 後回し方針＋共有 RW の整合/運用増で上回らない。

## Consequences
- 容易になる: 高速で再現可能なノード起動、テスト済みバージョンの pin、認証情報を AMI に埋め込まない（mpm はライセンス不要で DL、認証は実行時対話）。
- 難しくなる/要監視: AMI 肥大（root ボリューム拡大・スナップショット費・ビルド時間）。MATLAB 更新は AMI 再ビルド + `ami_id` 再 pin。
- 監視: AMI サイズとビルド時間。痛くなれば C（共有ボリューム）を再検討。
- 未確定: 焼き込む製品セット（既定は MATLAB/Simulink + 主要 Toolbox。サイズに直結するため要レビュー）。
