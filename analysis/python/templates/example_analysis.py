"""
ETRA 解析テンプレート — Python 基本解析
=========================================
使用方法:
  1. このファイルを personal/<username>/ にコピー
  2. INPUT_PREFIX / OUTPUT_PREFIX を自分のパスに変更
  3. JupyterLab または EC2 上で実行

依存: numpy, scipy, matplotlib, pandas, boto3
"""

import io
import os

import boto3
import matplotlib
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import signal

matplotlib.use("Agg")  # GUI なし環境向け

# ─── 設定 ───────────────────────────────────────────────
BUCKET = os.environ.get("WORKSPACE_BUCKET", "etra-dev-workspace")
INPUT_PREFIX = "personal/<your-user-id>/input/"
OUTPUT_PREFIX = "personal/<your-user-id>/results/"

s3 = boto3.client("s3")


# ─── S3 ヘルパー ─────────────────────────────────────────
def read_csv_from_s3(key: str) -> pd.DataFrame:
    """S3 から CSV を DataFrame として読み込む"""
    obj = s3.get_object(Bucket=BUCKET, Key=key)
    return pd.read_csv(io.BytesIO(obj["Body"].read()))


def save_figure_to_s3(fig: plt.Figure, key: str) -> None:
    """matplotlib Figure を PNG として S3 に保存"""
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=150, bbox_inches="tight")
    buf.seek(0)
    s3.put_object(Bucket=BUCKET, Key=key, Body=buf, ContentType="image/png")
    print(f"保存: s3://{BUCKET}/{key}")


def save_csv_to_s3(df: pd.DataFrame, key: str) -> None:
    """DataFrame を CSV として S3 に保存"""
    buf = io.BytesIO()
    df.to_csv(buf, index=False)
    buf.seek(0)
    s3.put_object(Bucket=BUCKET, Key=key, Body=buf, ContentType="text/csv")
    print(f"保存: s3://{BUCKET}/{key}")


# ─── 解析処理 ─────────────────────────────────────────────
def run_analysis() -> None:
    # ── サンプルデータ生成（実際は read_csv_from_s3 で読み込む）──
    t = np.linspace(0, 10, 1000)
    signal_data = np.sin(2 * np.pi * t) + 0.3 * np.random.randn(len(t))

    # ── フィルタリング ─────────────────────────────────────
    b, a = signal.butter(4, 0.1)
    filtered = signal.filtfilt(b, a, signal_data)

    # ── 統計量 ────────────────────────────────────────────
    stats = pd.DataFrame({
        "metric": ["mean", "std", "max", "min"],
        "raw": [signal_data.mean(), signal_data.std(), signal_data.max(), signal_data.min()],
        "filtered": [filtered.mean(), filtered.std(), filtered.max(), filtered.min()],
    })
    print(stats.to_string(index=False))

    # ── プロット ──────────────────────────────────────────
    fig, axes = plt.subplots(2, 1, figsize=(10, 6), sharex=True)
    axes[0].plot(t, signal_data, alpha=0.6, label="raw")
    axes[0].plot(t, filtered, label="filtered")
    axes[0].legend()
    axes[0].set_title("Signal")

    freqs, psd = signal.welch(filtered, fs=100)
    axes[1].semilogy(freqs, psd)
    axes[1].set_xlabel("Frequency [Hz]")
    axes[1].set_title("PSD")

    fig.tight_layout()

    # ── S3 に保存 ─────────────────────────────────────────
    save_figure_to_s3(fig, f"{OUTPUT_PREFIX}signal_plot.png")
    save_csv_to_s3(stats, f"{OUTPUT_PREFIX}stats.csv")
    plt.close(fig)


if __name__ == "__main__":
    run_analysis()
