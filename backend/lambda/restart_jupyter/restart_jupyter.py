"""
restart_jupyter Lambda — POST /compute/restart-jupyter
                         GET  /connect/dcv-token
呼び出したユーザーの EC2 インスタンスで JupyterLab 再起動 / DCV トークン生成を行う。
SSM Run Command (AWS-RunShellScript) を使用。
"""
import json
import os
import time
import boto3
from shared.auth import get_caller_user_id, get_caller_groups

REGION = os.environ.get("REGION", "us-east-1")
TAG_KEY = os.environ.get("ANALYSIS_INSTANCE_TAG_KEY", "Project")
TAG_VALUE = os.environ.get("ANALYSIS_INSTANCE_TAG_VALUE", "etra")

ec2 = boto3.client("ec2", region_name=REGION)
ssm = boto3.client("ssm", region_name=REGION)


def handler(event: dict, context) -> dict:
    try:
        user_id = get_caller_user_id(event)
        groups = get_caller_groups(event)
    except Exception:
        return _resp(401, {"error": "Unauthorized"})

    path = event.get("requestContext", {}).get("http", {}).get("path", "")
    if "dcv-token" in path:
        return _handle_dcv_token(user_id, groups)

    body = {}
    if event.get("body"):
        try:
            body = json.loads(event["body"])
        except Exception:
            pass

    requested_instance_id = body.get("instance_id")

    try:
        filters = [{"Name": f"tag:{TAG_KEY}", "Values": [TAG_VALUE]},
                   {"Name": "instance-state-name", "Values": ["running"]}]

        # admin は instance_id 指定で任意インスタンスを対象にできる
        # 一般ユーザーは自分の Owner タグのインスタンスのみ
        is_admin = "admin" in groups
        if is_admin and requested_instance_id:
            filters.append({"Name": "instance-id", "Values": [requested_instance_id]})
        else:
            filters.append({"Name": "tag:Owner", "Values": [user_id]})

        resp = ec2.describe_instances(Filters=filters)
        instances = [i for r in resp["Reservations"] for i in r["Instances"]]
    except Exception as e:
        return _resp(500, {"error": str(e)})

    if not instances:
        return _resp(404, {"error": "実行中のインスタンスが見つかりません"})

    instance_id = instances[0]["InstanceId"]

    # SSM Agent が登録済みかを確認（新規起動直後は未登録のことがある）
    try:
        ssm_info = ssm.describe_instance_information(
            Filters=[{"Key": "InstanceIds", "Values": [instance_id]}]
        )
        if not ssm_info.get("InstanceInformationList"):
            return _resp(503, {"error": "インスタンスがまだ SSM に接続されていません。1〜2 分後に再試行してください。"})
    except Exception as e:
        return _resp(500, {"error": str(e)})

    try:
        repair_script = """#!/bin/bash
set -euo pipefail
exec >> /var/log/jupyter-repair.log 2>&1
echo "=== jupyter repair start: $(date) ==="

# JupyterLab がインストールされていなければインストール
if ! command -v jupyter &>/dev/null; then
  echo "jupyter not found. installing..."
  pip3 install "jupyterlab>=4.0,<5.0" ipywidgets jupyterlab-widgets
fi

JUPYTER_BIN=$(which jupyter)
echo "jupyter: $JUPYTER_BIN"

# ワークスペースディレクトリ
mkdir -p /home/ec2-user/workspace
chown ec2-user:ec2-user /home/ec2-user/workspace

# Jupyter 設定
mkdir -p /home/ec2-user/.jupyter
cat > /home/ec2-user/.jupyter/jupyter_lab_config.py <<'JEOF'
c.ServerApp.ip = '127.0.0.1'
c.ServerApp.port = 8888
c.ServerApp.open_browser = False
c.ServerApp.token = ''
c.ServerApp.password = ''
c.ServerApp.root_dir = '/home/ec2-user/workspace'
c.ServerApp.allow_remote_access = False
JEOF
chown -R ec2-user:ec2-user /home/ec2-user/.jupyter

# systemd サービス再生成
cat > /etc/systemd/system/jupyterlab.service <<SEOF
[Unit]
Description=JupyterLab
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/workspace
ExecStart=${JUPYTER_BIN} lab
Restart=on-failure
RestartSec=10
Environment=PATH=/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
SEOF

systemctl daemon-reload
systemctl enable jupyterlab
systemctl restart jupyterlab
echo "=== jupyter repair done: $(date) ==="
"""
        cmd = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName="AWS-RunShellScript",
            Parameters={"commands": [repair_script]},
            Comment=f"repair and restart jupyterlab for {user_id}",
            TimeoutSeconds=60,
        )
        command_id = cmd["Command"]["CommandId"]
    except Exception as e:
        return _resp(500, {"error": str(e)})

    return _resp(200, {
        "instance_id": instance_id,
        "command_id": command_id,
        "message": "JupyterLab の再起動を開始しました",
    })


def _handle_dcv_token(user_id: str, groups: list) -> dict:
    import secrets
    is_admin = "admin" in groups
    filters = [
        {"Name": f"tag:{TAG_KEY}", "Values": [TAG_VALUE]},
        {"Name": "instance-state-name", "Values": ["running"]},
    ]
    if not is_admin:
        filters.append({"Name": "tag:Owner", "Values": [user_id]})

    try:
        resp = ec2.describe_instances(Filters=filters)
        instances = [i for r in resp["Reservations"] for i in r["Instances"]]
    except Exception as e:
        return _resp(500, {"error": str(e)})

    if not instances:
        return _resp(404, {"error": "実行中のインスタンスが見つかりません"})

    instance_id = instances[0]["InstanceId"]

    try:
        ssm_info = ssm.describe_instance_information(
            Filters=[{"Key": "InstanceIds", "Values": [instance_id]}]
        )
        if not ssm_info.get("InstanceInformationList"):
            return _resp(503, {"error": "インスタンスがまだ SSM に接続されていません。"})
    except Exception as e:
        return _resp(500, {"error": str(e)})

    # ランダムな一時パスワードを生成して ec2-user に設定
    temp_password = secrets.token_urlsafe(12)
    script = f"echo 'ec2-user:{temp_password}' | chpasswd"

    try:
        cmd = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName="AWS-RunShellScript",
            Parameters={"commands": [script]},
            Comment=f"dcv-password for {user_id}",
            TimeoutSeconds=30,
        )
        command_id = cmd["Command"]["CommandId"]
    except Exception as e:
        return _resp(500, {"error": str(e)})

    # 完了を待つ（最大 10 秒）
    for _ in range(20):
        time.sleep(0.5)
        try:
            result = ssm.get_command_invocation(
                CommandId=command_id, InstanceId=instance_id
            )
            status = result["Status"]
            if status == "Success":
                break
            if status in ("Failed", "Cancelled", "TimedOut"):
                err = result.get("StandardErrorContent", "")
                return _resp(500, {"error": f"パスワード設定失敗: {err}"})
        except ssm.exceptions.InvocationDoesNotExist:
            continue

    return _resp(200, {
        "url": "https://localhost:8443",
        "password": temp_password,
        "username": "ec2-user",
        "expires_in": 300,
        "instance_id": instance_id,
    })


def _resp(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }
