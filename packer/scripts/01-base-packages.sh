#!/bin/bash
set -euo pipefail
exec >> /var/log/packer-build.log 2>&1
echo "=== 01-base-packages start: $(date) ==="

dnf update -y
dnf install -y \
  amazon-ssm-agent \
  git \
  htop \
  jq \
  unzip \
  tmux \
  gcc \
  gcc-c++ \
  make \
  openssl-devel \
  bzip2-devel \
  libffi-devel \
  zlib-devel \
  python3.11 \
  python3.11-pip \
  python3.11-devel

# python3.11 を python3.11 として使えるようにするが、system の python3（dnf が依存）は上書きしない
ln -sf /usr/bin/python3.11 /usr/local/bin/python3.11
ln -sf /usr/bin/pip3.11 /usr/local/bin/pip3.11

# userdata から書き込むインスタンス固有の設定ディレクトリ
mkdir -p /etc/etra
chmod 755 /etc/etra

echo "=== 01-base-packages done: $(date) ==="
