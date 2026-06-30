"""boto3 クライアントファクトリ。テスト時はモック差し替えを想定。"""
import os
from typing import Any

import boto3


def ec2_client() -> Any:
    return boto3.client("ec2", region_name=os.environ["REGION"])


def s3_client() -> Any:
    return boto3.client("s3", region_name=os.environ["REGION"])


def sns_client() -> Any:
    return boto3.client("sns", region_name=os.environ["REGION"])


def cloudwatch_client() -> Any:
    return boto3.client("cloudwatch", region_name=os.environ["REGION"])


def medical_imaging_client() -> Any:
    return boto3.client("medical-imaging", region_name=os.environ["REGION"])
