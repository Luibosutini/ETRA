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


def _get_claims(event: dict) -> dict:
    """API Gateway v1 / v2 両形式から JWT claims を取得する。

    v2 (HTTP API): requestContext.authorizer.jwt.claims
    v1 (REST API): requestContext.authorizer.claims
    """
    ctx = event.get("requestContext", {})
    authorizer = ctx.get("authorizer", {})
    # v2 形式を優先
    jwt_block = authorizer.get("jwt", {})
    if jwt_block:
        return jwt_block.get("claims", {})
    # v1 フォールバック
    return authorizer.get("claims", {})


def get_caller_user_id(event: dict) -> str:
    """API Gateway の requestContext から Cognito ユーザー ID を取得する。

    HTTP API v2 / REST API v1 の両形式に対応する。
    """
    claims = _get_claims(event)
    user_id = claims.get("sub", "")
    if not user_id:
        raise PermissionError("Unauthenticated request")
    return user_id


def get_caller_groups(event: dict) -> list[str]:
    """呼び出し元が所属する Cognito グループのリストを返す。

    v2 JWT では cognito:groups が JSON 配列文字列 '["admin","user"]' で来る場合がある。
    """
    claims = _get_claims(event)
    groups_val = claims.get("cognito:groups", "")
    if not groups_val:
        return []
    # JWT パーサーが既にリストに変換済みの場合
    if isinstance(groups_val, list):
        return [g for g in groups_val if isinstance(g, str)]
    # JSON 配列形式（v2）をパース
    if groups_val.startswith("["):
        try:
            parsed = json.loads(groups_val)
            return [g.strip() for g in parsed if isinstance(g, str)]
        except json.JSONDecodeError:
            pass
        # API Gateway HTTP API 形式: "[admin user]"（スペース区切り・括弧付き）
        inner = groups_val[1:-1].strip()
        return [g for g in inner.split() if g]
    # カンマ区切り形式（v1）
    return [g.strip() for g in groups_val.split(",") if g.strip()]


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
