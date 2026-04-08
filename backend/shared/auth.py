"""Cognito JWT から呼び出し元ユーザー情報を取得するヘルパー。"""
import json
import base64
from typing import Any


def _decode_jwt_payload(token: str) -> dict[str, Any]:
    """JWT の Payload 部分をデコードする（署名検証なし）。
    本番では Cognito の JWKS による署名検証を行うこと。
    API Gateway の Cognito Authorizer を使用する場合は検証済み。
    """
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("Invalid JWT format")
    payload = parts[1]
    # base64url パディング補正
    padding = 4 - len(payload) % 4
    if padding != 4:
        payload += "=" * padding
    return json.loads(base64.urlsafe_b64decode(payload))


def get_caller_user_id(event: dict) -> str:
    """API Gateway の requestContext から Cognito ユーザー ID を取得する。

    Cognito Authorizer を使用している場合は requestContext.authorizer.claims に
    ユーザー情報が含まれる。
    """
    ctx = event.get("requestContext", {})
    claims = ctx.get("authorizer", {}).get("claims", {})
    user_id = claims.get("sub", "")
    if not user_id:
        raise PermissionError("Unauthenticated request")
    return user_id


def get_caller_groups(event: dict) -> list[str]:
    """呼び出し元が所属する Cognito グループのリストを返す。"""
    ctx = event.get("requestContext", {})
    claims = ctx.get("authorizer", {}).get("claims", {})
    groups_str = claims.get("cognito:groups", "")
    if not groups_str:
        return []
    return [g.strip() for g in groups_str.split(",")]


def is_admin(event: dict) -> bool:
    return "admin" in get_caller_groups(event)


def assert_workspace_access(user_id: str, s3_key: str) -> None:
    """利用者が対象の S3 キーにアクセス可能か検証する。

    Rules:
    - personal/<user_id>/ は本人のみアクセス可
    - shared/ は全員アクセス可
    - results/<user_id>/ は本人のみアクセス可
    """
    if s3_key.startswith("personal/"):
        owner = s3_key.split("/")[1] if s3_key.count("/") >= 1 else ""
        if owner != user_id:
            raise PermissionError(f"Access denied: {s3_key}")
    elif s3_key.startswith("results/"):
        owner = s3_key.split("/")[1] if s3_key.count("/") >= 1 else ""
        if owner != user_id:
            raise PermissionError(f"Access denied: {s3_key}")
    elif s3_key.startswith("shared/"):
        pass  # 全員アクセス可
    else:
        raise PermissionError(f"Unknown workspace path: {s3_key}")
