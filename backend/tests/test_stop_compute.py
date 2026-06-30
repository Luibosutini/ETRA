import json
import sys

import boto3
from moto import mock_aws

sys.path.insert(0, ".")
sys.path.insert(0, "lambda/stop_compute")

from conftest import make_api_event


@mock_aws
def test_stop_running_instance(monkeypatch):
    """稼働中インスタンスをタグ検索で停止できる。"""
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

    import stop_compute
    event = make_api_event(method="POST", groups=["admin"])
    resp = stop_compute.handler(event, None)

    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert instance.id in body["stopped"]


@mock_aws
def test_stop_no_running_instance():
    """稼働中インスタンスがない場合は空リストを返す。"""
    import stop_compute
    event = make_api_event(method="POST", groups=["admin"])
    resp = stop_compute.handler(event, None)
    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert body["stopped"] == []


@mock_aws
def test_scheduled_stop_skips_auth():
    """EventBridge スケジュールからの呼び出し（requestContext なし）は認証をスキップする。"""
    import stop_compute
    event = {
        "source": "scheduled-auto-stop",
        "tag_key": "Project",
        "tag_value": "etra",
    }
    resp = stop_compute.handler(event, None)
    assert resp["statusCode"] == 200


@mock_aws
def test_stop_requires_admin():
    """管理者以外は 403 を返す。"""
    import stop_compute
    event = make_api_event(method="POST", groups=["user"])
    resp = stop_compute.handler(event, None)
    assert resp["statusCode"] == 403
