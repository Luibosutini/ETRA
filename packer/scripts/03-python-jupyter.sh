#!/bin/bash
set -euo pipefail
echo "=== 03-python-jupyter start: $(date) ==="

pip3.11 install --upgrade pip
pip3.11 install \
  "jupyterlab>=4.0,<5.0" \
  "numpy>=2.0,<3.0" \
  "scipy>=1.13,<2.0" \
  "pandas>=2.0,<3.0" \
  "matplotlib>=3.8,<4.0" \
  "boto3>=1.0,<2.0" \
  "pydicom" \
  "Pillow" \
  "scikit-image" \
  "ipywidgets" \
  "jupyterlab-widgets"

# JupyterLab 設定（ec2-user 用）
mkdir -p /home/ec2-user/.jupyter
cat > /home/ec2-user/.jupyter/jupyter_lab_config.py <<'EOF'
c.ServerApp.ip = '127.0.0.1'
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.token = ''
c.ServerApp.password = ''
c.ServerApp.root_dir = '/home/ec2-user/workspace'
c.ServerApp.allow_remote_access = False
EOF

chown -R ec2-user:ec2-user /home/ec2-user/.jupyter

# ワークスペースディレクトリ
sudo -u ec2-user mkdir -p /home/ec2-user/workspace/{personal,shared,results}

echo "=== 03-python-jupyter done: $(date) ==="
