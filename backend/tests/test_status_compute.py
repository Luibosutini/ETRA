import json
import sys

import boto3
from moto import mock_aws

sys.path.insert(0, ".")
sys.path.insert(0, "lambda/status_compute")

from conftest import make_api_event


def _project_instance_tags(owner: str) -> list[dict[str, str]]:
    return [
        {"Key": "Project", "Value": "etra"},
        {"Key": "Owner", "Value": owner},
    ]


@mock_aws
def test_list_instances():
    ec2 = boto3.resource("ec2", region_name="us-east-1")
    owned = ec2.create_instances(
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
    )[0]
    ec2.create_instances(
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

    import status_compute

    event = make_api_event(groups=["user"])
    resp = status_compute.handler(event, None)

    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert len(body["instances"]) == 1
    assert body["instances"][0]["instance_id"] == owned.id
    assert body["instances"][0]["instance_type"] == "t3.xlarge"
    assert body["instances"][0]["owner"] == "user-001"


@mock_aws
def test_get_specific_instance():
    ec2 = boto3.resource("ec2", region_name="us-east-1")
    instances = ec2.create_instances(
        ImageId="ami-00000000", MinCount=1, MaxCount=1, InstanceType="t3.xlarge"
    )
    instance_id = instances[0].id

    import status_compute

    event = make_api_event(query_params={"instance_id": instance_id})
    resp = status_compute.handler(event, None)

    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert body["instances"][0]["instance_id"] == instance_id


@mock_aws
def test_unauthenticated_returns_403():
    import status_compute

    resp = status_compute.handler({"requestContext": {"authorizer": {"claims": {}}}}, None)
    assert resp["statusCode"] == 403
