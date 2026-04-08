"""boto3 クライアントファクトリ。テスト時はモック差し替えを想定。"""
import os
import boto3


def ec2_client():
    return boto3.client("ec2", region_name=os.environ["REGION"])


def s3_client():
    return boto3.client("s3", region_name=os.environ["REGION"])


def sns_client():
    return boto3.client("sns", region_name=os.environ["REGION"])
