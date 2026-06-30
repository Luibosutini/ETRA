#!/bin/bash
set -euo pipefail
echo "=== 02-desktop-xfce start: $(date) ==="

# AL2023 で確実に存在するパッケージのみ個別インストール（1つ失敗しても継続）
for pkg in \
  xorg-x11-server-Xorg \
  xorg-x11-xinit \
  xorg-x11-utils \
  dbus-x11 \
  mesa-dri-drivers \
  mesa-libGL \
  libXrender \
  libXtst \
  libXi \
  libXext \
  libX11 \
  gtk3 \
  gtk2 \
  xterm; do
  dnf install -y "$pkg" || echo "WARN: $pkg not found, skipping"
done

# XFCE（Amazon Linux 2023 で利用可能な場合）
dnf groupinstall -y "Xfce" 2>/dev/null || \
  dnf install -y \
    xfce4-session \
    xfwm4 \
    xfce4-panel \
    xfdesktop \
    xfce4-terminal \
    Thunar 2>/dev/null || true

# ─────────────────────────────────────────
# DCV virtual session 用デスクトップ起動設定
# virtual session では DCV が専用の X ディスプレイ(Xdcv)を起動し、
# 接続ユーザーの ~/.xsession を実行してデスクトップを立ち上げる。
# console 用の LightDM / Xvfb(:0) は virtual session では使われないため設定しない。
# ─────────────────────────────────────────
# dbus は xfce4-session の起動に必須
dnf install -y dbus dbus-x11 || echo "WARN: dbus install skipped"

cat > /home/ec2-user/.xsession <<'XS'
#!/bin/bash
# DCV virtual session desktop launcher for ec2-user
export XDG_SESSION_TYPE=x11
if command -v startxfce4 >/dev/null 2>&1; then
  exec startxfce4
else
  exec xfce4-session
fi
XS
chown ec2-user:ec2-user /home/ec2-user/.xsession
chmod 755 /home/ec2-user/.xsession

echo "=== 02-desktop-xfce done: $(date) ==="
