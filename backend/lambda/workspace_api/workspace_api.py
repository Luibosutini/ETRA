"""S3 ワークスペース操作 API。

エンドポイント（HTTP メソッド + パス）:
    GET    /workspace        → ファイル一覧（prefix 指定可）
    GET    /workspace/{key+} → ファイルダウンロード URL（presigned）
    PUT    /workspace/{key+} → ファイルアップロード URL（presigned）
    DELETE /workspace/{key+} → ファイル削除

環境変数:
    REGION: AWS リージョン
    WORKSPACE_BUCKET: S3 バケット名
"""
import json
import logging
import os
import sys
import urllib.parse

sys.path.insert(0, "/opt/python")

from shared.aws_clients import s3_client
from shared.auth import assert_workspace_access, get_caller_user_id
from shared.response import bad_request, forbidden, not_found, ok, server_error

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

BUCKET = os.environ["WORKSPACE_BUCKET"]
PRESIGNED_EXPIRY = 900  # 15 分


def _list_objects(s3, prefix: str) -> list[dict]:
    paginator = s3.get_paginator("list_objects_v2")
    items = []
    for page in paginator.paginate(Bucket=BUCKET, Prefix=prefix, Delimiter="/"):
        for obj in page.get("Contents", []):
            items.append({
                "key": obj["Key"],
                "size": obj["Size"],
                "last_modified": obj["LastModified"].isoformat(),
            })
        for cp in page.get("CommonPrefixes", []):
            items.append({"key": cp["Prefix"], "size": None, "last_modified": None})
    return items


def handler(event: dict, context: object) -> dict:
    logger.info("Event: %s", json.dumps(event))

    try:
        user_id = get_caller_user_id(event)
    except PermissionError as e:
        return forbidden(str(e))

    method = event.get("httpMethod", "GET")
    path_params = event.get("pathParameters") or {}
    raw_key: str = path_params.get("key", "")
    s3_key = urllib.parse.unquote(raw_key)
    query_params = event.get("queryStringParameters") or {}

    try:
        s3 = s3_client()

        if method == "GET" and not s3_key:
            prefix = query_params.get("prefix", f"personal/{user_id}/")
            assert_workspace_access(user_id, prefix)
            items = _list_objects(s3, prefix)
            return ok({"items": items, "prefix": prefix})

        if not s3_key:
            return bad_request("key is required")

        assert_workspace_access(user_id, s3_key)

        if method == "GET":
            url = s3.generate_presigned_url(
                "get_object",
                Params={"Bucket": BUCKET, "Key": s3_key},
                ExpiresIn=PRESIGNED_EXPIRY,
            )
            return ok({"url": url, "expires_in": PRESIGNED_EXPIRY})

        if method == "PUT":
            content_type = query_params.get("content_type", "application/octet-stream")
            url = s3.generate_presigned_url(
                "put_object",
                Params={"Bucket": BUCKET, "Key": s3_key, "ContentType": content_type},
                ExpiresIn=PRESIGNED_EXPIRY,
            )
            return ok({"url": url, "expires_in": PRESIGNED_EXPIRY})

        if method == "DELETE":
            # shared/dropbox/ 以外の削除は本人のみ（assert_workspace_access で確認済み）
            s3.delete_object(Bucket=BUCKET, Key=s3_key)
            logger.info("Deleted: %s by %s", s3_key, user_id)
            return ok({"deleted": s3_key})

        return bad_request(f"Unsupported method: {method}")

    except PermissionError as e:
        return forbidden(str(e))
    except s3.exceptions.NoSuchKey:
        return not_found(s3_key)
    except Exception as e:
        logger.exception("Unexpected error")
        return server_error(str(e))
