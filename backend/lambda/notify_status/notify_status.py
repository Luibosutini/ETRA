"""EC2 状態変更イベントを受け取り SNS で通知する Lambda 関数。

EventBridge ルール（EC2 Instance State-change Notification）から呼ばれる。

環境変数:
    REGION: AWS リージョン
    NOTIFICATION_TOPIC_ARN: 通知先 SNS トピック ARN
"""
import json
import logging
import os
import sys
from typing import Any

sys.path.insert(0, "/opt/python")

from shared.aws_clients import sns_client

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# 通知対象とする状態変化
NOTIFY_STATES = {"running", "stopped", "terminated"}


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    logger.info("Event: %s", json.dumps(event))

    detail = event.get("detail", {})
    instance_id = detail.get("instance-id", "")
    state = detail.get("state", "")

    if state not in NOTIFY_STATES:
        logger.info("Skipping notification for state: %s", state)
        return {"skipped": True, "state": state}

    topic_arn = os.environ.get("NOTIFICATION_TOPIC_ARN", "")
    if not topic_arn:
        logger.warning("NOTIFICATION_TOPIC_ARN is not set; skipping SNS publish")
        return {"skipped": True, "reason": "no topic configured"}

    message = {
        "instance_id": instance_id,
        "state": state,
        "region": event.get("region", os.environ.get("REGION", "")),
        "time": event.get("time", ""),
    }
    subject = f"[医用画像解析基盤] EC2 {instance_id}: {state}"

    sns = sns_client()
    try:
        resp = sns.publish(
            TopicArn=topic_arn,
            Subject=subject,
            Message=json.dumps(message, ensure_ascii=False, indent=2),
        )
        logger.info("Published message: %s", resp["MessageId"])
        return {"message_id": resp["MessageId"], "instance_id": instance_id, "state": state}
    except Exception:
        logger.exception("Failed to publish SNS message")
        raise
