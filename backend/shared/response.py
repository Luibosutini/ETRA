"""API Gateway 向け HTTP レスポンスヘルパー。"""
import json
from typing import Any

_CORS_HEADERS: dict[str, str] = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
}


def ok(body: Any) -> dict[str, Any]:
    return {"statusCode": 200, "headers": _CORS_HEADERS, "body": json.dumps(body)}


def bad_request(message: str) -> dict[str, Any]:
    return {"statusCode": 400, "headers": _CORS_HEADERS, "body": json.dumps({"error": message})}


def forbidden(message: str = "Forbidden") -> dict[str, Any]:
    return {"statusCode": 403, "headers": _CORS_HEADERS, "body": json.dumps({"error": message})}


def not_found(message: str = "Not found") -> dict[str, Any]:
    return {"statusCode": 404, "headers": _CORS_HEADERS, "body": json.dumps({"error": message})}


def server_error(message: str = "Internal server error") -> dict[str, Any]:
    return {"statusCode": 500, "headers": _CORS_HEADERS, "body": json.dumps({"error": message})}
