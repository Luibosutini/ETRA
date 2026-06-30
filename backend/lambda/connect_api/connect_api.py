"""
connect_api Lambda — GET /connect/credentials
Cognito JWT で認証済みのユーザーに、SSM ポートフォワーディング専用の
一時 IAM クレデンシャルを発行する。
"""
import json
import os
from typing import Any

import boto3
from shared.auth import get_caller_user_id

SSM_CONNECT_ROLE_ARN = os.environ["SSM_CONNECT_ROLE_ARN"]
REGION = os.environ.get("REGION", "us-east-1")

sts = boto3.client("sts", region_name=REGION)


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    try:
        user_id = get_caller_user_id(event)
    except Exception:
        return _resp(401, {"error": "Unauthorized"})

    # RoleSessionName は英数字とアンダースコア/ハイフンのみ許可
    session_name = "".join(c if c.isalnum() or c in "-_" else "_" for c in user_id)[:64]

    try:
        assumed = sts.assume_role(
            RoleArn=SSM_CONNECT_ROLE_ARN,
            RoleSessionName=session_name,
            DurationSeconds=3600,
        )
    except Exception as e:
        return _resp(500, {"error": str(e)})

    creds = assumed["Credentials"]
    return _resp(200, {
        "access_key_id":     creds["AccessKeyId"],
        "secret_access_key": creds["SecretAccessKey"],
        "session_token":     creds["SessionToken"],
        "expiration":        creds["Expiration"].isoformat(),
        "region":            REGION,
    })


def _resp(status: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
