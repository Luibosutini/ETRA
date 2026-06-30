import json
import sys

import boto3
import pytest
from moto import mock_aws

sys.path.insert(0, ".")
sys.path.insert(0, "lambda/stop_compute")

from conftest import make_api_event


def _project_instance_tags(owner: str) -> list[dict[str, str]]:
    return [
        {"Key": "Project", "Value": "etra"},
        {"Key": "Owner", "Value": owner},
    ]


@mock_aws
def test_stop_running_instance():
    ec2 = boto3.resource("ec2", region_name="us-east-1")
    instances = ec2.create_instances(
        ImageId="ami-00000000",
        MinCount=1,
        MaxCount=1,
        InstanceType="t3.xlarge",
        TagSpecifications=[
            {
                "ResourceType": "instance",
                "Tags": _project_instance_tags("user-001"),
            }
        ],
    )
    instance = instances[0]

    import stop_compute

    event = make_api_event(method="POST", groups=["user"])
    resp = stop_compute.handler(event, None)

    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert instance.id in body["stopped"]


@mock_aws
def test_stop_no_running_instance():
    import stop_compute

    event = make_api_event(method="POST", groups=["admin"])
    resp = stop_compute.handler(event, None)
    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert body["stopped"] == []


@pytest.mark.xfail(
    reason="stop_compute currently rejects EventBridge-style events without requestContext",
    strict=True,
)
@mock_aws
def test_scheduled_stop_skips_auth():
    ec2 = boto3.resource("ec2", region_name="us-east-1")
    instances = ec2.create_instances(
        ImageId="ami-00000000",
        MinCount=1,
        MaxCount=1,
        InstanceType="t3.xlarge",
        TagSpecifications=[
            {
                "ResourceType": "instance",
                "Tags": _project_instance_tags("user-001"),
            }
        ],
    )

    import stop_compute

    event = {
        "source": "scheduled-auto-stop",
        "tag_key": "Project",
        "tag_value": "etra",
    }
    resp = stop_compute.handler(event, None)

    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert instances[0].id in body["stopped"]


@mock_aws
def test_stop_non_admin_cannot_stop_other_users_instance():
    ec2 = boto3.resource("ec2", region_name="us-east-1")
    instances = ec2.create_instances(
        ImageId="ami-00000000",
        MinCount=1,
        MaxCount=1,
        InstanceType="t3.xlarge",
        TagSpecifications=[
            {
                "ResourceType": "instance",
                "Tags": _project_instance_tags("user-002"),
            }
        ],
    )
    instance = instances[0]

    import stop_compute

    event = make_api_event(
        method="POST",
        body={"instance_id": instance.id},
        groups=["user"],
    )
    resp = stop_compute.handler(event, None)

    assert resp["statusCode"] == 403
    assert json.loads(resp["body"])["error"] == "Cannot stop an instance you do not own"
