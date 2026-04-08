"""EC2 解析ノードを停止する Lambda 関数。

EventBridge スケジュール（自動停止）と API Gateway（手動停止）の両方から呼ばれる。

環境変数:
    REGION: AWS リージョン
    ANALYSIS_INSTANCE_TAG_KEY: 停止対象を絞り込む EC2 タグキー
    ANALYSIS_INSTANCE_TAG_VALUE: 停止対象を絞り込む EC2 タグ値
"""
import json
import logging
import os
import sys

sys.path.insert(0, "/opt/python")

from shared.aws_clients import ec2_client
from shared.auth import get_caller_user_id, is_admin
from shared.response import bad_request, forbidden, ok, server_error

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

TAG_KEY = os.environ.get("ANALYSIS_INSTANCE_TAG_KEY", "Project")
TAG_VALUE = os.environ.get("ANALYSIS_INSTANCE_TAG_VALUE", "")


def _find_running_instances(ec2, instance_id: str | None, tag_key: str, tag_value: str) -> list[str]:
    if instance_id:
        return [instance_id]

    resp = ec2.describe_instances(
        Filters=[
            {"Name": f"tag:{tag_key}", "Values": [tag_value]},
            {"Name": "instance-state-name", "Values": ["running", "pending"]},
        ]
    )
    return [
        i["InstanceId"]
        for r in resp["Reservations"]
        for i in r["Instances"]
    ]


def handler(event: dict, context: object) -> dict:
    logger.info("Event: %s", json.dumps(event))

    # EventBridge スケジュール経由（requestContext なし）
    is_scheduled = "requestContext" not in event

    if not is_scheduled:
        try:
            get_caller_user_id(event)
        except PermissionError as e:
            return forbidden(str(e))
        if not is_admin(event):
            return forbidden("Only admin users can stop compute nodes")

    # スケジュール実行時は event から tag_key / tag_value を取得できる
    body: dict = {}
    if event.get("body"):
        try:
            body = json.loads(event["body"])
        except json.JSONDecodeError:
            return bad_request("Invalid JSON body")

    instance_id: str | None = body.get("instance_id") or event.get("instance_id")
    tag_key = event.get("tag_key", TAG_KEY)
    tag_value = event.get("tag_value", TAG_VALUE)

    ec2 = ec2_client()
    try:
        targets = _find_running_instances(ec2, instance_id, tag_key, tag_value)
        if not targets:
            logger.info("No running instances found; nothing to stop")
            return ok({"stopped": [], "message": "No running instances"})

        ec2.stop_instances(InstanceIds=targets)
        logger.info("Stopped instances: %s", targets)
        return ok({"stopped": targets})
    except Exception as e:
        logger.exception("Failed to stop instances")
        return server_error(str(e))
