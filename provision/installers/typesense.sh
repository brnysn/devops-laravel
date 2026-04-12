#!/bin/bash

# Typesense sunucusu (DEB). API anahtarı: /etc/typesense/typesense-server.ini
VER="${installs_typesense_version:-26.0}"
API_KEY="${installs_typesense_api_key:-change-me-typesense-key}"
API_ADDRESS="${installs_typesense_api_address:-127.0.0.1}"
API_PORT="${installs_typesense_api_port:-8108}"
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

CONFIG_FILE="/etc/typesense/typesense-server.ini"
if [ ! -f "${CONFIG_FILE}.bak" ] && [ -f "$CONFIG_FILE" ]; then
  sudo cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
fi

if [ ! -f "$CONFIG_FILE" ]; then
  sudo install -d /etc/typesense
  sudo touch "$CONFIG_FILE"
fi

set_typesense_config() {
  local key="$1"
  local value="$2"
  local escaped_value

  escaped_value=$(printf '%s' "$value" | sed 's/[\\&|]/\\&/g')
  if sudo grep -q "^${key}[[:space:]]*=" "$CONFIG_FILE"; then
    sudo sed -i "s|^${key}[[:space:]]*=.*|${key} = ${escaped_value}|" "$CONFIG_FILE"
  else
    printf '%s = %s\n' "$key" "$value" | sudo tee -a "$CONFIG_FILE" >/dev/null
  fi
}

set_typesense_config "api-key" "$API_KEY"
set_typesense_config "api-address" "$API_ADDRESS"
set_typesense_config "api-port" "$API_PORT"

sudo systemctl enable typesense-server
sudo systemctl restart typesense-server
