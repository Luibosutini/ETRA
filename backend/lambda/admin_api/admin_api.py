"""admin_api Lambda — Cognito ユーザー・グループ管理 API

エンドポイント（admin グループのみ）:
  GET    /admin/users
  POST   /admin/users/{username}/groups/{group}
  DELETE /admin/users/{username}/groups/{group}
"""
import json
import os

import boto3

from shared.auth import get_caller_groups

cognito = boto3.client("cognito-idp")
USER_POOL_ID = os.environ["USER_POOL_ID"]


def _response(status: int, body: object) -> dict:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str),
    }


def _require_admin(event: dict) -> bool:
    groups = get_caller_groups(event)
    return "admin" in groups


def _get_method(event: dict) -> str:
    ctx = event.get("requestContext", {})
    return ctx.get("http", {}).get("method", event.get("httpMethod", "GET")).upper()


def _get_path(event: dict) -> str:
    ctx = event.get("requestContext", {})
    return ctx.get("http", {}).get("path", event.get("path", ""))


def handler(event: dict, _context) -> dict:
    # ログ出力（Authorization ヘッダー除外）
    log_event = {k: v for k, v in event.items() if k != "headers"}
    print(json.dumps(log_event, default=str))

    if not _require_admin(event):
        return _response(403, {"error": "Forbidden: admin only"})

    method = _get_method(event)
    path = _get_path(event)
    path_params = event.get("pathParameters") or {}

    # GET /admin/users
    if method == "GET" and "/admin/users" in path and "groups" not in path:
        return _list_users()

    # POST /admin/users/{username}/groups/{group}
    if method == "POST" and "groups" in path:
        username = path_params.get("username", "")
        group = path_params.get("group", "")
        return _add_user_to_group(username, group)

    # DELETE /admin/users/{username}/groups/{group}
    if method == "DELETE" and "groups" in path:
        username = path_params.get("username", "")
        group = path_params.get("group", "")
        return _remove_user_from_group(username, group)

    return _response(404, {"error": "Not found"})


def _list_users() -> dict:
    users = []
    paginator = cognito.get_paginator("list_users")
    for page in paginator.paginate(UserPoolId=USER_POOL_ID):
        for u in page["Users"]:
            username = u["Username"]
            attrs = {a["Name"]: a["Value"] for a in u.get("Attributes", [])}
            # グループを取得
            groups_resp = cognito.admin_list_groups_for_user(
                UserPoolId=USER_POOL_ID, Username=username
            )
            groups = [g["GroupName"] for g in groups_resp.get("Groups", [])]
            users.append({
                "username": username,
                "email": attrs.get("email", ""),
                "status": u.get("UserStatus", ""),
                "enabled": u.get("Enabled", True),
                "groups": groups,
                "created": u.get("UserCreateDate"),
            })
    return _response(200, {"users": users})


def _add_user_to_group(username: str, group: str) -> dict:
    if not username or not group:
        return _response(400, {"error": "username and group are required"})
    cognito.admin_add_user_to_group(
        UserPoolId=USER_POOL_ID, Username=username, GroupName=group
    )
    return _response(200, {"message": f"Added {username} to {group}"})


def _remove_user_from_group(username: str, group: str) -> dict:
    if not username or not group:
        return _response(400, {"error": "username and group are required"})
    cognito.admin_remove_user_from_group(
        UserPoolId=USER_POOL_ID, Username=username, GroupName=group
    )
    return _response(200, {"message": f"Removed {username} from {group}"})
