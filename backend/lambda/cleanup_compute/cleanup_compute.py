"""EC2 解析ノード自動クリーンアップ Lambda 関数。

EventBridge で 15 分ごとに実行される。以下を行う:
1. CPU アイドル検知: 実行中インスタンスの CPU 平均が閾値以下なら停止
2. 長期停止 terminate: N 日間 stopped のインスタンスを削除

環境変数:
    REGION: AWS リージョン
    ANALYSIS_INSTANCE_TAG_KEY / ANALYSIS_INSTANCE_TAG_VALUE: 対象タグ
    IDLE_CPU_THRESHOLD: アイドル判定 CPU 使用率（デフォルト 5.0）
    IDLE_DURATION_MINUTES: アイドル判定期間（デフォルト 30）
    STOPPED_DAYS_THRESHOLD: terminate するまでの停止日数（デフォルト 7）
"""
import json
import logging
import os
import re
import sys
from datetime import UTC, datetime, timedelta

sys.path.insert(0, "/opt/python")

from shared.aws_clients import cloudwatch_client, ec2_client

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

TAG_KEY = os.environ.get("ANALYSIS_INSTANCE_TAG_KEY", "Project")
TAG_VALUE = os.environ.get("ANALYSIS_INSTANCE_TAG_VALUE", "")
IDLE_CPU_THRESHOLD = float(os.environ.get("IDLE_CPU_THRESHOLD", "5.0"))
IDLE_DURATION_MINUTES = int(os.environ.get("IDLE_DURATION_MINUTES", "30"))
STOPPED_DAYS_THRESHOLD = int(os.environ.get("STOPPED_DAYS_THRESHOLD", "7"))


def _get_avg_cpu(cw, instance_id: str, minutes: int) -> float | None:
    """指定期間の平均 CPU 使用率を返す。データ不足時は None。"""
    end = datetime.now(UTC)
    start = end - timedelta(minutes=minutes)
    resp = cw.get_metric_statistics(
        Namespace="AWS/EC2",
        MetricName="CPUUtilization",
        Dimensions=[{"Name": "InstanceId", "Value": instance_id}],
        StartTime=start,
        EndTime=end,
        Period=minutes * 60,
        Statistics=["Average"],
    )
    datapoints = resp.get("Datapoints", [])
    if not datapoints:
        return None
    return datapoints[0]["Average"]


def _parse_state_transition_time(reason: str) -> datetime | None:
    """StateTransitionReason から停止時刻を取得する。
    例: "User initiated (2024-01-01 12:00:00 GMT)"
    """
    m = re.search(r"\((\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) GMT\)", reason)
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S").replace(tzinfo=UTC)
    except ValueError:
        return None


def handler(event: dict, context: object) -> dict:
    logger.info("Cleanup started")

    ec2 = ec2_client()
    cw = cloudwatch_client()
    project_filter = [{"Name": f"tag:{TAG_KEY}", "Values": [TAG_VALUE]}]

    stopped_ids: list[str] = []
    terminated_ids: list[str] = []

    try:
        # ─── 1. CPU アイドル検知 → stop ───
        resp = ec2.describe_instances(
            Filters=project_filter + [{"Name": "instance-state-name", "Values": ["running"]}]
        )
        running = [i for r in resp["Reservations"] for i in r["Instances"]]

        for inst in running:
            iid = inst["InstanceId"]
            avg_cpu = _get_avg_cpu(cw, iid, IDLE_DURATION_MINUTES)
            if avg_cpu is None:
                logger.info("No CPU data for %s, skipping", iid)
                continue
            if avg_cpu < IDLE_CPU_THRESHOLD:
                ec2.stop_instances(InstanceIds=[iid])
                logger.info("Stopped idle instance %s (avg CPU %.1f%%)", iid, avg_cpu)
                stopped_ids.append(iid)

        # ─── 2. 長期停止 → terminate ───
        resp = ec2.describe_instances(
            Filters=project_filter + [{"Name": "instance-state-name", "Values": ["stopped"]}]
        )
        stopped = [i for r in resp["Reservations"] for i in r["Instances"]]
        threshold = datetime.now(UTC) - timedelta(days=STOPPED_DAYS_THRESHOLD)

        for inst in stopped:
            iid = inst["InstanceId"]
            reason = inst.get("StateTransitionReason", "")
            stopped_at = _parse_state_transition_time(reason)
            if stopped_at and stopped_at < threshold:
                ec2.terminate_instances(InstanceIds=[iid])
                logger.info("Terminated instance %s (stopped since %s)", iid, stopped_at)
                terminated_ids.append(iid)

        logger.info("Cleanup done. stopped=%s terminated=%s", stopped_ids, terminated_ids)
        return {
            "statusCode": 200,
            "body": json.dumps({"stopped": stopped_ids, "terminated": terminated_ids}),
        }

    except Exception:
        logger.exception("Cleanup error")
        raise
