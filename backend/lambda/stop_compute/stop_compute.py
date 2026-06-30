"""EC2 解析ノードを停止する Lambda 関数（per-user 構成）。

ユーザーは自分の Owner タグが付いたインスタンスのみ停止可能。

環境変数:
    REGION: AWS リージョン
    ANALYSIS_INSTANCE_TAG_KEY: プロジェクト絞り込みタグキー
    ANALYSIS_INSTANCE_TAG_VALUE: プロジェクト絞り込みタグ値
"""
import json
import logging
import os
import sys
from typing import Any

sys.path.insert(0, "/opt/python")

from shared.auth import get_caller_user_id, is_admin
from shared.aws_clients import ec2_client
from shared.response import bad_request, forbidden, ok, server_error

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

TAG_KEY = os.environ.get("ANALYSIS_INSTANCE_TAG_KEY", "Project")
TAG_VALUE = os.environ.get("ANALYSIS_INSTANCE_TAG_VALUE", "")


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    safe_event = {k: v for k, v in event.items() if k != "headers"}
    logger.info("Event: %s", json.dumps(safe_event))

    if "requestContext" not in event:
        return bad_request("Direct invocation not supported")

    try:
        user_id = get_caller_user_id(event)
    except PermissionError as e:
        return forbidden(str(e))

    body: dict[str, Any] = {}
    if event.get("body"):
        try:
            body = json.loads(event["body"])
        except json.JSONDecodeError:
            return bad_request("Invalid JSON body")

    instance_id: str | None = body.get("instance_id")

    admin = is_admin(event)
    ec2 = ec2_client()
    try:
        # admin は全インスタンス、一般ユーザーは自分の Owner タグのみ対象
        filters = [
            {"Name": f"tag:{TAG_KEY}", "Values": [TAG_VALUE]},
            {"Name": "instance-state-name", "Values": ["running", "pending"]},
        ]
        if not admin:
            filters.append({"Name": "tag:Owner", "Values": [user_id]})

        resp = ec2.describe_instances(Filters=filters)
        targets = [i["InstanceId"] for r in resp["Reservations"] for i in r["Instances"]]

        if instance_id:
            if not admin and instance_id not in targets:
                return forbidden("Cannot stop an instance you do not own")
            targets = [instance_id]

        if not targets:
            return ok({"stopped": [], "message": "No running instances"})

        ec2.stop_instances(InstanceIds=targets)
        safe_targets = [str(t).replace("\n", "").replace("\r", "") for t in targets]
        logger.info("Stopped instances: %s by user: %s", safe_targets, user_id)
        return ok({"stopped": targets})

    except Exception as e:
        logger.exception("Failed to stop instances")
        return server_error(str(e))
