"""Cognito Post-confirmation トリガー。

ユーザーがメール確認を完了した直後に呼ばれる。
`user` グループへ自動追加し、API アクセスを有効にする。

Cognito はこの関数の戻り値として event をそのまま返すことを期待する。
例外を送出するとサインアップ自体が失敗するため、グループ追加の失敗はログのみに留める。

環境変数:
    USER_POOL_ID: Cognito ユーザープール ID（event.userPoolId のフォールバック用）
"""
import logging
import os
from typing import Any

import boto3

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

DEFAULT_GROUP = "user"


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    trigger_source = event.get("triggerSource", "")
    username = event.get("userName", "")
    user_pool_id = event.get("userPoolId") or os.environ.get("USER_POOL_ID", "")

    logger.info("Post-confirmation: triggerSource=%s userName=%s", trigger_source, username)

    # メール確認完了以外（管理者による強制確認など）は何もしない
    if trigger_source != "PostConfirmation_ConfirmSignUp":
        logger.info("Skipping: triggerSource is not ConfirmSignUp")
        return event

    if not username or not user_pool_id:
        logger.error("Missing userName or userPoolId; skipping group assignment")
        return event

    client = boto3.client(
        "cognito-idp",
        region_name=os.environ.get("AWS_REGION", "us-east-1"),
    )
    try:
        client.admin_add_user_to_group(
            UserPoolId=user_pool_id,
            Username=username,
            GroupName=DEFAULT_GROUP,
        )
        logger.info("Added %s to group '%s'", username, DEFAULT_GROUP)
    except client.exceptions.ResourceNotFoundException:
        logger.error("Group '%s' not found in pool %s", DEFAULT_GROUP, user_pool_id)
    except Exception:
        logger.exception("Failed to add user %s to group", username)
        # サインアップを失敗させないため例外は再送出しない

    return event
