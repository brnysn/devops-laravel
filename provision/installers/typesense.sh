#!/bin/bash

# Typesense sunucusu (DEB). API anahtarı: /etc/typesense/typesense-server.ini
VER="${installs_typesense_version:-26.0}"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) DEB_ARCH=amd64 ;;
  aarch64|arm64) DEB_ARCH=arm64 ;;
  *)
    error "Typesense: desteklenmeyen mimari: $ARCH (amd64/arm64 bekleniyor)"
    exit 1
    ;;
esac

TMP_DEB="/tmp/typesense-server-${VER}-${DEB_ARCH}.deb"
URL="https://dl.typesense.org/releases/${VER}/typesense-server-${VER}-${DEB_ARCH}.deb"

curl -fsSL "$URL" -o "$TMP_DEB"
sudo apt-get install -y "$TMP_DEB"
rm -f "$TMP_DEB"

sudo systemctl enable typesense-server
sudo systemctl restart typesense-server
