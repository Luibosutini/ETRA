"""EC2 解析ノードを起動する Lambda 関数。

環境変数:
    REGION: AWS リージョン
    ANALYSIS_INSTANCE_TAG_KEY: 起動対象を絞り込む EC2 タグキー
    ANALYSIS_INSTANCE_TAG_VALUE: 起動対象を絞り込む EC2 タグ値
"""
import json
import logging
import os
import sys

sys.path.insert(0, "/opt/python")  # Lambda Layer / パッケージパス

from shared.aws_clients import ec2_client
from shared.auth import get_caller_user_id, is_admin
from shared.response import bad_request, forbidden, ok, server_error

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

TAG_KEY = os.environ.get("ANALYSIS_INSTANCE_TAG_KEY", "Project")
TAG_VALUE = os.environ.get("ANALYSIS_INSTANCE_TAG_VALUE", "")


def _find_instance(ec2, instance_id: str | None) -> str:
    """instance_id が指定されていればそのまま返す。なければタグで検索する。"""
    if instance_id:
        return instance_id

    resp = ec2.describe_instances(
        Filters=[
            {"Name": f"tag:{TAG_KEY}", "Values": [TAG_VALUE]},
            {"Name": "instance-state-name", "Values": ["stopped"]},
        ]
    )
    instances = [
        i
        for r in resp["Reservations"]
        for i in r["Instances"]
    ]
    if not instances:
        raise ValueError("No stopped analysis instance found")
    if len(instances) > 1:
        raise ValueError("Multiple stopped instances found; specify instance_id explicitly")
    return instances[0]["InstanceId"]


def handler(event: dict, context: object) -> dict:
    logger.info("Event: %s", json.dumps(event))

    # 認証チェック（API Gateway 経由の場合）
    if "requestContext" in event:
        try:
            user_id = get_caller_user_id(event)
        except PermissionError as e:
            return forbidden(str(e))

        if not is_admin(event):
            return forbidden("Only admin users can start compute nodes")

    body: dict = {}
    if event.get("body"):
        try:
            body = json.loads(event["body"])
        except json.JSONDecodeError:
            return bad_request("Invalid JSON body")

    instance_id: str | None = body.get("instance_id") or event.get("instance_id")

    ec2 = ec2_client()
    try:
        target_id = _find_instance(ec2, instance_id)
        ec2.start_instances(InstanceIds=[target_id])
        logger.info("Started instance: %s", target_id)
        return ok({"instance_id": target_id, "state": "starting"})
    except ValueError as e:
        return bad_request(str(e))
    except Exception as e:
        logger.exception("Failed to start instance")
        return server_error(str(e))
