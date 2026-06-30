"""HealthImaging DICOM スタディ照会 API。

エンドポイント（HTTP メソッド + パス）:
    GET /dicom/studies → ImageSet（スタディ）一覧
        クエリ: max_results（既定 25、1〜50）
                next_token（ページネーション継続トークン）
                patient_id（DICOMPatientId の完全一致フィルタ）

環境変数:
    REGION: AWS リージョン
    DATASTORE_ID: HealthImaging データストア ID
"""
import json
import logging
import os
import sys
from typing import Any

sys.path.insert(0, "/opt/python")

from shared.auth import get_caller_user_id
from shared.aws_clients import medical_imaging_client
from shared.response import bad_request, forbidden, ok, server_error

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

DATASTORE_ID = os.environ["DATASTORE_ID"]

DEFAULT_MAX_RESULTS = 25
MAX_RESULTS_LIMIT = 50


def _to_study(summary: dict[str, Any]) -> dict[str, Any]:
    """SearchImageSets の summary をポータル向けのフラットな形式に変換する。"""
    tags = summary.get("DICOMTags", {})
    created_at = summary.get("createdAt")
    updated_at = summary.get("updatedAt")
    return {
        "image_set_id": summary.get("imageSetId"),
        "version": summary.get("version"),
        "study_instance_uid": tags.get("DICOMStudyInstanceUID"),
        "patient_id": tags.get("DICOMPatientId"),
        "patient_name": tags.get("DICOMPatientName"),
        "study_date": tags.get("DICOMStudyDate"),
        "study_description": tags.get("DICOMStudyDescription"),
        "series_count": tags.get("DICOMNumberOfStudyRelatedSeries"),
        "instance_count": tags.get("DICOMNumberOfStudyRelatedInstances"),
        "is_primary": summary.get("isPrimary"),
        "created_at": created_at.isoformat() if created_at else None,
        "updated_at": updated_at.isoformat() if updated_at else None,
    }


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    # headers には Authorization が含まれるため除外してログ出力
    safe_event = {k: v for k, v in event.items() if k != "headers"}
    logger.info("Event: %s", json.dumps(safe_event))

    try:
        user_id = get_caller_user_id(event)
    except PermissionError as e:
        return forbidden(str(e))

    query_params = event.get("queryStringParameters") or {}

    raw_max = query_params.get("max_results", str(DEFAULT_MAX_RESULTS))
    try:
        max_results = int(raw_max)
    except ValueError:
        return bad_request(f"Invalid max_results: {raw_max}")
    max_results = max(1, min(max_results, MAX_RESULTS_LIMIT))

    kwargs: dict[str, Any] = {"datastoreId": DATASTORE_ID, "maxResults": max_results}
    if query_params.get("next_token"):
        kwargs["nextToken"] = query_params["next_token"]
    if query_params.get("patient_id"):
        kwargs["searchCriteria"] = {
            "filters": [{
                "operator": "EQUAL",
                "values": [{"DICOMPatientId": query_params["patient_id"]}],
            }]
        }

    try:
        client = medical_imaging_client()
        resp = client.search_image_sets(**kwargs)
        studies = [_to_study(s) for s in resp.get("imageSetsMetadataSummaries", [])]
        logger.info("SearchImageSets: %d studies by %s", len(studies), user_id)
        return ok({"studies": studies, "next_token": resp.get("nextToken")})
    except Exception as e:
        logger.exception("Unexpected error: %s", e)
        return server_error(str(e))
