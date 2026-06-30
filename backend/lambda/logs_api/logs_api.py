"""logs_api Lambda — CloudWatch Logs 参照 API

エンドポイント（admin グループのみ）:
  GET /logs              ロググループ一覧（Lambda 関数）
  GET /logs/events       最新ログイベント（?group=<name>&limit=<n>）
"""
import json
import os
import time

import boto3
from shared.auth import get_caller_groups

logs = boto3.client("logs")
LOG_GROUP_PREFIX = os.environ.get("LOG_GROUP_PREFIX", "/aws/lambda/")


def _response(status: int, body: object) -> dict:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str),
    }


def _require_admin(event: dict) -> bool:
    groups = get_caller_groups(event)
    return "admin" in groups


def _get_path(event: dict) -> str:
    ctx = event.get("requestContext", {})
    return ctx.get("http", {}).get("path", event.get("path", ""))


def handler(event: dict, _context) -> dict:
    log_event = {k: v for k, v in event.items() if k != "headers"}
    print(json.dumps(log_event, default=str))

    if not _require_admin(event):
        return _response(403, {"error": "Forbidden: admin only"})

    path = _get_path(event)
    qs = event.get("queryStringParameters") or {}

    # GET /logs/events
    if "/logs/events" in path:
        group = qs.get("group", "")
        limit = int(qs.get("limit", "50"))
        return _get_log_events(group, limit)

    # GET /logs
    return _list_log_groups()


def _list_log_groups() -> dict:
    groups = []
    paginator = logs.get_paginator("describe_log_groups")
    for page in paginator.paginate(logGroupNamePrefix=LOG_GROUP_PREFIX):
        for g in page["logGroups"]:
            groups.append(g["logGroupName"])
    return _response(200, {"groups": groups})


def _get_log_events(group: str, limit: int) -> dict:
    if not group:
        return _response(400, {"error": "group parameter is required"})

    # 直近 24 時間
    start_time = int((time.time() - 86400) * 1000)

    resp = logs.filter_log_events(
        logGroupName=group,
        startTime=start_time,
        limit=min(limit, 200),
    )
    events = [
        {
            "timestamp": e["timestamp"],
            "message": e["message"].rstrip("\n"),
            "stream": e["logStreamName"],
        }
        for e in resp.get("events", [])
    ]
    return _response(200, {"events": events})
