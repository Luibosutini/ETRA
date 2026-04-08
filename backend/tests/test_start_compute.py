import sys
import boto3
import pytest
from moto import mock_aws

sys.path.insert(0, ".")
sys.path.insert(0, "lambda/start_compute")

from conftest import make_api_event


@mock_aws
def test_start_instance_by_tag(monkeypatch):
    """タグ検索で停止中のインスタンスを起動できる。"""
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

    import start_compute
    event = make_api_event(method="POST", groups=["admin"])
    resp = start_compute.handler(event, None)

    assert resp["statusCode"] == 200
    import json
    body = json.loads(resp["body"])
    assert body["instance_id"] == instance.id
    assert body["state"] == "starting"


@mock_aws
def test_start_requires_admin():
    """管理者以外は 403 を返す。"""
    import start_compute
    event = make_api_event(method="POST", groups=["user"])
    resp = start_compute.handler(event, None)
    assert resp["statusCode"] == 403


@mock_aws
def test_start_no_stopped_instance():
    """停止中インスタンスがない場合は 400 を返す。"""
    import start_compute
    event = make_api_event(method="POST", groups=["admin"])
    resp = start_compute.handler(event, None)
    assert resp["statusCode"] == 400
