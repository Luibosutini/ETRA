"""
ETRA 解析テンプレート — DICOM 処理
====================================
AWS HealthImaging から画像を取得し、S3 ワークスペースへ結果を保存する。

使用方法:
  1. このファイルを personal/<username>/ にコピー
  2. DATASTORE_ID / IMAGE_SET_ID を実際の値に変更
  3. EC2 上（または JupyterLab）で実行

依存: boto3, pydicom, numpy, matplotlib
"""

import io
import json
import os

import boto3
import matplotlib
import matplotlib.pyplot as plt
import numpy as np

matplotlib.use("Agg")

# ─── 設定 ───────────────────────────────────────────────
WORKSPACE_BUCKET = os.environ.get("WORKSPACE_BUCKET", "etra-dev-workspace")
OUTPUT_PREFIX = "personal/<your-user-id>/results/"

DATASTORE_ID = "<your-datastore-id>"
IMAGE_SET_ID = "<your-image-set-id>"

medical_imaging = boto3.client("medical-imaging", region_name="us-east-1")
s3 = boto3.client("s3")


# ─── HealthImaging ヘルパー ──────────────────────────────
def get_image_set_metadata(datastore_id: str, image_set_id: str) -> dict:
    """ImageSet のメタデータを取得"""
    resp = medical_imaging.get_image_set_metadata(
        datastoreId=datastore_id,
        imageSetId=image_set_id,
    )
    raw = resp["imageSetMetadataBlob"].read()
    return json.loads(raw)


def list_dicom_series(metadata: dict) -> list[dict]:
    """メタデータからシリーズ一覧を抽出"""
    series_list = []
    study = metadata.get("Study", {})
    for series_uid, series in study.get("Series", {}).items():
        series_list.append({
            "series_uid": series_uid,
            "modality": series.get("DICOM", {}).get("Modality", ""),
            "description": series.get("DICOM", {}).get("SeriesDescription", ""),
            "instance_count": len(series.get("Instances", {})),
        })
    return series_list


def get_pixel_data(
    datastore_id: str,
    image_set_id: str,
    image_frame_id: str,
) -> np.ndarray:
    """HTJ2K 圧縮ピクセルデータを取得して numpy 配列に変換"""
    resp = medical_imaging.get_image_frame(
        datastoreId=datastore_id,
        imageSetId=image_set_id,
        imageFrameInformation={"imageFrameId": image_frame_id},
    )
    raw = resp["imageFrameBlob"].read()

    # HTJ2K デコードには imagecodecs が必要
    # pip install imagecodecs
    try:
        import imagecodecs
        return imagecodecs.openjpeg_decode(raw)
    except ImportError:
        # フォールバック: 生バイトを返す（デコード不可）
        return np.frombuffer(raw, dtype=np.uint8)


# ─── 解析処理 ─────────────────────────────────────────────
def save_figure_to_s3(fig: plt.Figure, key: str) -> None:
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=150, bbox_inches="tight")
    buf.seek(0)
    s3.put_object(Bucket=WORKSPACE_BUCKET, Key=key, Body=buf, ContentType="image/png")
    print(f"保存: s3://{WORKSPACE_BUCKET}/{key}")


def run_analysis() -> None:
    print(f"ImageSet: {IMAGE_SET_ID}")

    # メタデータ取得
    metadata = get_image_set_metadata(DATASTORE_ID, IMAGE_SET_ID)
    series_list = list_dicom_series(metadata)
    print(f"シリーズ数: {len(series_list)}")
    for s in series_list:
        print(f"  {s['series_uid']}: {s['modality']} - {s['description']} ({s['instance_count']} instances)")

    # 最初のシリーズの最初のインスタンスを取得（サンプル）
    study = metadata.get("Study", {})
    first_series = next(iter(study.get("Series", {}).values()), {})
    first_instance = next(iter(first_series.get("Instances", {}).values()), {})
    frames = first_instance.get("ImageFrames", [])

    if not frames:
        print("フレームが見つかりません")
        return

    frame_id = frames[0].get("ID", "")
    pixel_data = get_pixel_data(DATASTORE_ID, IMAGE_SET_ID, frame_id)

    # 2D 画像として表示（サンプル）
    if pixel_data.ndim >= 2:
        fig, ax = plt.subplots(1, 1, figsize=(8, 8))
        ax.imshow(pixel_data if pixel_data.ndim == 2 else pixel_data[:, :, 0], cmap="gray")
        ax.set_title(f"Frame: {frame_id[:8]}...")
        ax.axis("off")
        save_figure_to_s3(fig, f"{OUTPUT_PREFIX}dicom_preview.png")
        plt.close(fig)
        print("プレビュー画像を保存しました")


if __name__ == "__main__":
    run_analysis()
