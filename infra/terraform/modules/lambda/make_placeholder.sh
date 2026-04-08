#!/bin/bash
set -euo pipefail

# Terraform apply 前に placeholder.zip を生成するスクリプト
# 本番のコードは backend/lambda/ でビルドし scripts/deploy/ でデプロイする

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_FILE="${TMPDIR:-/tmp}/_placeholder.py"
OUT_ZIP="${SCRIPT_DIR}/placeholder.zip"

echo "# placeholder" > "${TMP_FILE}"

if command -v zip >/dev/null 2>&1; then
  zip -j "${OUT_ZIP}" "${TMP_FILE}"
else
  python - "${TMP_FILE}" "${OUT_ZIP}" <<'PY'
import pathlib
import sys
import zipfile

tmp_file = pathlib.Path(sys.argv[1])
out_zip = pathlib.Path(sys.argv[2])

with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    zf.write(tmp_file, arcname=tmp_file.name)
PY
fi

rm -f "${TMP_FILE}"
echo "placeholder.zip created: ${OUT_ZIP}"