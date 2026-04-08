import sys
import json
import boto3
from moto import mock_aws

sys.path.insert(0, ".")
sys.path.insert(0, "lambda/workspace_api")

from conftest import make_api_event

BUCKET = "test-workspace"


@mock_aws
def test_list_personal_files():
    """自分の personal/ 配下をリストできる。"""
    s3 = boto3.client("s3", region_name="us-east-1")
    s3.create_bucket(Bucket=BUCKET)
    s3.put_object(Bucket=BUCKET, Key="personal/user-001/data.csv", Body=b"a,b,c")

    import workspace_api
    event = make_api_event(
        method="GET",
        query_params={"prefix": "personal/user-001/"},
        user_id="user-001",
    )
    resp = workspace_api.handler(event, None)

    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    keys = [i["key"] for i in body["items"]]
    assert "personal/user-001/data.csv" in keys


@mock_aws
def test_cannot_access_other_users_personal():
    """他ユーザーの personal/ にはアクセスできない。"""
    import workspace_api
    event = make_api_event(
        method="GET",
        query_params={"prefix": "personal/other-user/"},
        user_id="user-001",
    )
    resp = workspace_api.handler(event, None)
    assert resp["statusCode"] == 403


@mock_aws
def test_get_presigned_url():
    """GET でダウンロード用 presigned URL を取得できる。"""
    s3 = boto3.client("s3", region_name="us-east-1")
    s3.create_bucket(Bucket=BUCKET)
    s3.put_object(Bucket=BUCKET, Key="shared/templates/template.py", Body=b"pass")

    import workspace_api
    event = make_api_event(
        method="GET",
        path_params={"key": "shared/templates/template.py"},
        user_id="user-001",
    )
    resp = workspace_api.handler(event, None)

    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert "url" in body


@mock_aws
def test_put_presigned_url():
    """PUT でアップロード用 presigned URL を取得できる。"""
    s3 = boto3.client("s3", region_name="us-east-1")
    s3.create_bucket(Bucket=BUCKET)

    import workspace_api
    event = make_api_event(
        method="PUT",
        path_params={"key": "personal/user-001/result.csv"},
        user_id="user-001",
    )
    resp = workspace_api.handler(event, None)
    assert resp["statusCode"] == 200
    assert "url" in json.loads(resp["body"])


@mock_aws
def test_delete_own_file():
    """自分の personal/ ファイルを削除できる。"""
    s3 = boto3.client("s3", region_name="us-east-1")
    s3.create_bucket(Bucket=BUCKET)
    s3.put_object(Bucket=BUCKET, Key="personal/user-001/old.csv", Body=b"x")

    import workspace_api
    event = make_api_event(
        method="DELETE",
        path_params={"key": "personal/user-001/old.csv"},
        user_id="user-001",
    )
    resp = workspace_api.handler(event, None)
    assert resp["statusCode"] == 200
