"""EC2 解析ノードを起動する Lambda 関数（per-user ハイブリッド構成）。

ユーザーごとに Owner タグでインスタンスを管理する。
- stopped 状態のインスタンスがあれば start_instances
- インスタンスが存在しなければ Launch Template から run_instances

環境変数:
    REGION: AWS リージョン
    LAUNCH_TEMPLATE_ID: EC2 起動テンプレート ID
    ANALYSIS_INSTANCE_TAG_KEY: プロジェクト絞り込みタグキー
    ANALYSIS_INSTANCE_TAG_VALUE: プロジェクト絞り込みタグ値
"""
import json
import logging
import os
import sys

sys.path.insert(0, "/opt/python")

from shared.aws_clients import ec2_client
from shared.auth import get_caller_user_id
from shared.response import bad_request, forbidden, ok, server_error

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

LAUNCH_TEMPLATE_ID = os.environ.get("LAUNCH_TEMPLATE_ID", "")
TAG_KEY = os.environ.get("ANALYSIS_INSTANCE_TAG_KEY", "Project")
TAG_VALUE = os.environ.get("ANALYSIS_INSTANCE_TAG_VALUE", "")


def _find_user_instance(ec2, user_id: str) -> dict | None:
    """ユーザーのインスタンスを返す（terminated を除く）。"""
    resp = ec2.describe_instances(
        Filters=[
            {"Name": "tag:Owner", "Values": [user_id]},
            {"Name": f"tag:{TAG_KEY}", "Values": [TAG_VALUE]},
            {"Name": "instance-state-name", "Values": ["pending", "running", "stopping", "stopped"]},
        ]
    )
    instances = [i for r in resp["Reservations"] for i in r["Instances"]]
    return instances[0] if instances else None


def handler(event: dict, context: object) -> dict:
    safe_event = {k: v for k, v in event.items() if k != "headers"}
    logger.info("Event: %s", json.dumps(safe_event))

    if "requestContext" not in event:
        return bad_request("Direct invocation not supported")

    try:
        user_id = get_caller_user_id(event)
    except PermissionError as e:
        return forbidden(str(e))

    ec2 = ec2_client()
    try:
        instance = _find_user_instance(ec2, user_id)

        if instance:
            state = instance["State"]["Name"]
            instance_id = instance["InstanceId"]
            safe_id = instance_id.replace("\n", "").replace("\r", "")

            if state == "running":
                return ok({"instance_id": instance_id, "state": "running", "message": "Already running"})

            if state in ("stopping", "pending"):
                return ok({"instance_id": instance_id, "state": state, "message": f"Instance is {state}"})

            # stopped → start
            ec2.start_instances(InstanceIds=[instance_id])
            logger.info("Started instance: %s for user: %s", safe_id, user_id)
            return ok({"instance_id": instance_id, "state": "starting"})

        # インスタンスなし → Launch Template から新規作成
        if not LAUNCH_TEMPLATE_ID:
            return server_error("LAUNCH_TEMPLATE_ID not configured")

        resp = ec2.run_instances(
            LaunchTemplate={"LaunchTemplateId": LAUNCH_TEMPLATE_ID, "Version": "$Latest"},
            MinCount=1,
            MaxCount=1,
            TagSpecifications=[
                {
                    "ResourceType": "instance",
                    "Tags": [{"Key": "Owner", "Value": user_id}],
                },
                {
                    "ResourceType": "volume",
                    "Tags": [{"Key": "Owner", "Value": user_id}],
                },
            ],
        )
        new_instance = resp["Instances"][0]
        instance_id = new_instance["InstanceId"]
        safe_id = instance_id.replace("\n", "").replace("\r", "")
        logger.info("Created instance: %s for user: %s", safe_id, user_id)
        return ok({"instance_id": instance_id, "state": "pending", "created": True})

    except Exception as e:
        logger.exception("Failed to start instance")
        return server_error(str(e))
