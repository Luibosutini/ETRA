import sys
import json
import boto3
import pytest
from moto import mock_aws

sys.path.insert(0, ".")
sys.path.insert(0, "lambda/notify_status")


def _eb_event(instance_id: str, state: str) -> dict:
    return {
        "source": "aws.ec2",
        "detail-type": "EC2 Instance State-change Notification",
        "region": "us-east-1",
        "time": "2026-01-01T00:00:00Z",
        "detail": {"instance-id": instance_id, "state": state},
    }


@mock_aws
def test_notify_on_running(monkeypatch):
    """running 状態変化で SNS に publish される。"""
    sns = boto3.client("sns", region_name="us-east-1")
    topic = sns.create_topic(Name="alerts")
    monkeypatch.setenv("NOTIFICATION_TOPIC_ARN", topic["TopicArn"])

    import notify_status
    resp = notify_status.handler(_eb_event("i-0123456789abcdef0", "running"), None)
    assert "message_id" in resp


@mock_aws
def test_skip_on_irrelevant_state():
    """通知対象外の状態変化はスキップされる。"""
    import notify_status
    resp = notify_status.handler(_eb_event("i-0123456789abcdef0", "pending"), None)
    assert resp.get("skipped") is True


@mock_aws
def test_skip_when_no_topic(monkeypatch):
    """NOTIFICATION_TOPIC_ARN が未設定の場合はスキップされる。"""
    monkeypatch.setenv("NOTIFICATION_TOPIC_ARN", "")
    import notify_status
    resp = notify_status.handler(_eb_event("i-0123456789abcdef0", "stopped"), None)
    assert resp.get("skipped") is True
