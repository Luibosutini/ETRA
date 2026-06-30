import importlib
import json
import sys

import boto3
from moto import mock_aws

sys.path.insert(0, ".")
sys.path.insert(0, "lambda/start_compute")

from conftest import make_api_event


def _owned_project_tags(owner: str = "user-001") -> list[dict[str, str]]:
    return [
        {"Key": "Project", "Value": "etra"},
        {"Key": "Owner", "Value": owner},
    ]


@mock_aws
def test_start_instance_by_tag():
    ec2 = boto3.resource("ec2", region_name="us-east-1")
    instances = ec2.create_instances(
        ImageId="ami-00000000",
        MinCount=1,
        MaxCount=1,
        InstanceType="t3.xlarge",
        TagSpecifications=[
            {
                "ResourceType": "instance",
                "Tags": _owned_project_tags(),
            }
        ],
    )
    instance = instances[0]
    instance.stop()
    instance.wait_until_stopped()

    import start_compute

    event = make_api_event(method="POST", groups=["admin"])
    resp = start_compute.handler(event, None)

    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert body["instance_id"] == instance.id
    assert body["state"] == "starting"


@mock_aws
def test_start_non_admin_can_start_owned_instance():
    ec2 = boto3.resource("ec2", region_name="us-east-1")
    instances = ec2.create_instances(
        ImageId="ami-00000000",
        MinCount=1,
        MaxCount=1,
        InstanceType="t3.xlarge",
        TagSpecifications=[
            {
                "ResourceType": "instance",
                "Tags": _owned_project_tags(),
            }
        ],
    )
    instance = instances[0]
    instance.stop()
    instance.wait_until_stopped()

    import start_compute

    event = make_api_event(method="POST", groups=["user"])
    resp = start_compute.handler(event, None)

    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert body["instance_id"] == instance.id
    assert body["state"] == "starting"


@mock_aws
def test_start_creates_instance_from_launch_template(monkeypatch):
    ec2 = boto3.client("ec2", region_name="us-east-1")
    lt = ec2.create_launch_template(
        LaunchTemplateName="analysis-node",
        LaunchTemplateData={
            "ImageId": "ami-00000000",
            "InstanceType": "t3.xlarge",
            "TagSpecifications": [
                {
                    "ResourceType": "instance",
                    "Tags": [{"Key": "Project", "Value": "etra"}],
                }
            ],
        },
    )
    monkeypatch.setenv("LAUNCH_TEMPLATE_ID", lt["LaunchTemplate"]["LaunchTemplateId"])

    import start_compute

    start_compute = importlib.reload(start_compute)
    event = make_api_event(method="POST", groups=["user"])
    resp = start_compute.handler(event, None)

    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert body["state"] == "pending"
    assert body["created"] is True

    created = ec2.describe_instances(InstanceIds=[body["instance_id"]])["Reservations"][0][
        "Instances"
    ][0]
    tags = {tag["Key"]: tag["Value"] for tag in created["Tags"]}
    assert tags["Owner"] == "user-001"
