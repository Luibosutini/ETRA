"""EC2 解析ノードの状態を照会する Lambda 関数（per-user 構成）。

一般ユーザーは自分の Owner タグが付いたインスタンスのみ返す。admin は全台返す。

環境変数:
    REGION: AWS リージョン
    ANALYSIS_INSTANCE_TAG_KEY / ANALYSIS_INSTANCE_TAG_VALUE: 対象タグ
"""
import json
import logging
import os
import sys

sys.path.insert(0, "/opt/python")

from shared.aws_clients import ec2_client
from shared.auth import get_caller_user_id, is_admin
from shared.response import bad_request, forbidden, not_found, ok, server_error

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

TAG_KEY = os.environ.get("ANALYSIS_INSTANCE_TAG_KEY", "Project")
TAG_VALUE = os.environ.get("ANALYSIS_INSTANCE_TAG_VALUE", "")


def _instance_summary(instance: dict) -> dict:
    tags = {t["Key"]: t["Value"] for t in instance.get("Tags", [])}
    return {
        "instance_id": instance["InstanceId"],
        "state": instance["State"]["Name"],
        "instance_type": instance["InstanceType"],
        "private_ip": instance.get("PrivateIpAddress"),
        "name": tags.get("Name", ""),
        "owner": tags.get("Owner", ""),
        "launch_time": instance["LaunchTime"].isoformat() if instance.get("LaunchTime") else None,
    }


def handler(event: dict, context: object) -> dict:
    safe_event = {k: v for k, v in event.items() if k != "headers"}
    logger.info("Event: %s", json.dumps(safe_event))

    if "requestContext" not in event:
        return bad_request("Direct invocation not supported")

    try:
        user_id = get_caller_user_id(event)
    except PermissionError as e:
        return forbidden(str(e))

    admin = is_admin(event)
    params = event.get("queryStringParameters") or {}
    instance_id: str | None = params.get("instance_id")

    ec2 = ec2_client()
    try:
        if instance_id:
            resp = ec2.describe_instances(InstanceIds=[instance_id])
        elif admin:
            # admin は全インスタンスを返す
            resp = ec2.describe_instances(
                Filters=[{"Name": f"tag:{TAG_KEY}", "Values": [TAG_VALUE]}]
            )
        else:
            # 一般ユーザーは自分のインスタンスのみ
            resp = ec2.describe_instances(
                Filters=[
                    {"Name": "tag:Owner", "Values": [user_id]},
                    {"Name": f"tag:{TAG_KEY}", "Values": [TAG_VALUE]},
                ]
            )

        instances = [
            _instance_summary(i)
            for r in resp["Reservations"]
            for i in r["Instances"]
            if i["State"]["Name"] != "terminated"
        ]

        if instance_id and not instances:
            return not_found(f"Instance {instance_id} not found")

        return ok({"instances": instances})

    except ec2.exceptions.ClientError as e:
        code = e.response["Error"]["Code"]
        if code == "InvalidInstanceID.NotFound":
            return not_found(f"Instance {instance_id} not found")
        logger.exception("EC2 error")
        return server_error(str(e))
    except Exception as e:
        logger.exception("Unexpected error")
        return server_error(str(e))
