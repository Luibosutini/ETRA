# analysis/python/scripts

EC2 上で定期実行または手動実行する Python スクリプトを配置する。

## ディレクトリ構成

```
scripts/
└── README.md   # このファイル
```

## 使用方法

```bash
# EC2 に SSH / SSM 接続後
cd ~/workspace
python scripts/run_analysis.py
```

## 注意

- スクリプトは `results/<user-id>/` に出力を保存すること。
- 入力は `personal/<user-id>/` または `shared/templates/` から読み込むこと。
- `shared/dropbox/` は 24 時間で自動削除されるため恒久保管に使用しないこと。
