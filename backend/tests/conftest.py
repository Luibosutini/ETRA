"""テスト共通フィクスチャ。"""
import os
import pytest
import boto3
from moto import mock_aws


# ─────────────────────────────────────────
# 環境変数のデフォルト設定
# ─────────────────────────────────────────
@pytest.fixture(autouse=True)
def aws_env(monkeypatch):
    monkeypatch.setenv("REGION", "us-east-1")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SECURITY_TOKEN", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("ANALYSIS_INSTANCE_TAG_KEY", "Project")
    monkeypatch.setenv("ANALYSIS_INSTANCE_TAG_VALUE", "etra")
    monkeypatch.setenv("WORKSPACE_BUCKET", "test-workspace")
    monkeypatch.setenv("NOTIFICATION_TOPIC_ARN", "")


# ─────────────────────────────────────────
# テスト用 EC2 インスタンスを作成するヘルパー
# ─────────────────────────────────────────
@pytest.fixture
def stopped_instance():
    """停止状態の EC2 インスタンスを作成して InstanceId を返す。"""
    with mock_aws():
        ec2 = boto3.resource("ec2", region_name="us-east-1")
        instances = ec2.create_instances(
            ImageId="ami-00000000",
            MinCount=1,
            MaxCount=1,
            InstanceType="t3.xlarge",
            TagSpecifications=[{
                "ResourceType": "instance",
                "Tags": [{"Key": "Project", "Value": "etra"}],
            }],
        )
        instance = instances[0]
        instance.stop()
        instance.wait_until_stopped()
        yield instance.id


# ─────────────────────────────────────────
# テスト用 S3 バケットを作成するヘルパー
# ─────────────────────────────────────────
@pytest.fixture
def workspace_bucket():
    with mock_aws():
        s3 = boto3.client("s3", region_name="us-east-1")
        s3.create_bucket(Bucket="test-workspace")
        yield "test-workspace"


# ─────────────────────────────────────────
# API Gateway イベントビルダー
# ─────────────────────────────────────────
def make_api_event(
    method: str = "GET",
    path: str = "/",
    path_params: dict | None = None,
    query_params: dict | None = None,
    body: dict | None = None,
    user_id: str = "user-001",
    groups: list[str] | None = None,
) -> dict:
    return {
        "httpMethod": method,
        "path": path,
        "pathParameters": path_params or {},
        "queryStringParameters": query_params or {},
        "body": __import__("json").dumps(body) if body else None,
        "requestContext": {
            "authorizer": {
                "claims": {
                    "sub": user_id,
                    "cognito:groups": ",".join(groups or []),
                }
            }
        },
    }
