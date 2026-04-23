# analysis/notebooks

JupyterLab ノートブック置き場。

## 使用方法

EC2 上で JupyterLab を起動し、SSM ポートフォワード経由でブラウザからアクセスする。

```bash
# EC2 側
jupyter lab --no-browser --port=8888

# ローカル側（Connect ページのコマンドをコピーして実行）
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8888"],"localPortNumber":["8888"]}'
```

ブラウザで `http://localhost:8888` を開く。

## ノートブックの保存

作業終了後は `personal/<user-id>/` に保存すること。

```python
import subprocess
subprocess.run([
    "aws", "s3", "cp",
    "MyAnalysis.ipynb",
    "s3://etra-dev-workspace/personal/<user-id>/MyAnalysis.ipynb"
])
```
