import json
import sys
from datetime import UTC, datetime
from unittest.mock import MagicMock

sys.path.insert(0, ".")
sys.path.insert(0, "lambda/dicom_api")

from conftest import make_api_event


def _summary(**overrides) -> dict:
    """SearchImageSets の imageSetsMetadataSummaries 1 件分のテストデータ。"""
    base = {
        "imageSetId": "imageset-001",
        "version": 1,
        "isPrimary": True,
        "createdAt": datetime(2026, 1, 31, 12, 0, 0, tzinfo=UTC),
        "updatedAt": datetime(2026, 2, 1, 12, 0, 0, tzinfo=UTC),
        "DICOMTags": {
            "DICOMStudyInstanceUID": "1.2.840.113619.2.1",
            "DICOMPatientId": "PAT001",
            "DICOMPatientName": "YAMADA^TARO",
            "DICOMStudyDate": "20260131",
            "DICOMStudyDescription": "CHEST CT",
            "DICOMNumberOfStudyRelatedSeries": 3,
            "DICOMNumberOfStudyRelatedInstances": 120,
        },
    }
    base.update(overrides)
    return base


def _mock_client(monkeypatch, response: dict) -> MagicMock:
    import dicom_api
    client = MagicMock()
    client.search_image_sets.return_value = response
    monkeypatch.setattr(dicom_api, "medical_imaging_client", lambda: client)
    return client


def test_list_studies(monkeypatch):
    """スタディ一覧を取得しフィールドがマッピングされる。"""
    import dicom_api
    client = _mock_client(
        monkeypatch,
        {"imageSetsMetadataSummaries": [_summary()], "nextToken": "token-abc"},
    )

    resp = dicom_api.handler(make_api_event(method="GET", path="/dicom/studies"), None)

    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert body["next_token"] == "token-abc"
    study = body["studies"][0]
    assert study["image_set_id"] == "imageset-001"
    assert study["study_instance_uid"] == "1.2.840.113619.2.1"
    assert study["patient_id"] == "PAT001"
    assert study["patient_name"] == "YAMADA^TARO"
    assert study["study_date"] == "20260131"
    assert study["study_description"] == "CHEST CT"
    assert study["series_count"] == 3
    assert study["instance_count"] == 120
    assert study["is_primary"] is True
    assert study["created_at"] == "2026-01-31T12:00:00+00:00"

    kwargs = client.search_image_sets.call_args.kwargs
    assert kwargs["datastoreId"] == "datastore-test-001"
    assert kwargs["maxResults"] == 25


def test_unauthenticated_returns_403(monkeypatch):
    """JWT claims がないリクエストは 403。"""
    import dicom_api
    _mock_client(monkeypatch, {"imageSetsMetadataSummaries": []})

    event = make_api_event(method="GET", path="/dicom/studies")
    event["requestContext"]["authorizer"]["claims"]["sub"] = ""
    resp = dicom_api.handler(event, None)
    assert resp["statusCode"] == 403


def test_invalid_max_results_returns_400(monkeypatch):
    """max_results が数値でない場合は 400。"""
    import dicom_api
    _mock_client(monkeypatch, {"imageSetsMetadataSummaries": []})

    event = make_api_event(
        method="GET", path="/dicom/studies", query_params={"max_results": "abc"}
    )
    resp = dicom_api.handler(event, None)
    assert resp["statusCode"] == 400


def test_max_results_clamped_to_limit(monkeypatch):
    """max_results は上限 50 にクランプされる。"""
    import dicom_api
    client = _mock_client(monkeypatch, {"imageSetsMetadataSummaries": []})

    event = make_api_event(
        method="GET", path="/dicom/studies", query_params={"max_results": "200"}
    )
    resp = dicom_api.handler(event, None)
    assert resp["statusCode"] == 200
    assert client.search_image_sets.call_args.kwargs["maxResults"] == 50


def test_patient_id_filter(monkeypatch):
    """patient_id 指定時は searchCriteria の EQUAL フィルタになる。"""
    import dicom_api
    client = _mock_client(monkeypatch, {"imageSetsMetadataSummaries": []})

    event = make_api_event(
        method="GET", path="/dicom/studies", query_params={"patient_id": "PAT001"}
    )
    resp = dicom_api.handler(event, None)
    assert resp["statusCode"] == 200
    criteria = client.search_image_sets.call_args.kwargs["searchCriteria"]
    assert criteria == {
        "filters": [{"operator": "EQUAL", "values": [{"DICOMPatientId": "PAT001"}]}]
    }


def test_next_token_passthrough(monkeypatch):
    """next_token は SearchImageSets の nextToken にそのまま渡される。"""
    import dicom_api
    client = _mock_client(monkeypatch, {"imageSetsMetadataSummaries": []})

    event = make_api_event(
        method="GET", path="/dicom/studies", query_params={"next_token": "token-xyz"}
    )
    resp = dicom_api.handler(event, None)
    assert resp["statusCode"] == 200
    assert client.search_image_sets.call_args.kwargs["nextToken"] == "token-xyz"
    body = json.loads(resp["body"])
    assert body["next_token"] is None
