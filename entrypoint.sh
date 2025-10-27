#!/bin/bash
set -euo pipefail

# Try to load the module painlessly (if kernel allows)
modprobe wireguard 2>/dev/null || true

# Make sure directories exist
mkdir -p /etc/wireguard
mkdir -p /data/wireguard /data/wireguard-clients

# If this is first start - and configs already exist in volume, load them
if [ ! -f /etc/wireguard/wg0.conf ] && [ -f /data/wireguard/wg0.conf ]; then
  cp -a /data/wireguard/* /etc/wireguard/
fi

# If wg0.conf doesn't exist yet - run installation (script won't write anything to sysctl/ufw if in container)
if [ ! -f /etc/wireguard/wg0.conf ]; then
  echo "▶️ Initial WireGuard installation in container..."
  NETWORK=${NETWORK:-10.0.0.0/24} \
  PORT=${PORT:-51820} \
  ENDPOINT=${ENDPOINT:-$(curl -fsS ifconfig.me || echo "CHANGE_ME")} \
  CLIENT_DEFAULT=${CLIENT_DEFAULT:-mobile1} \
  IN_CONTAINER=1 \
  bash /usr/local/bin/wg-autosetup.sh
fi

# Sync configs to volume (one-way) 
cp -a /etc/wireguard/* /data/wireguard/ 2>/dev/null || true

echo "▶️ Bringing up wg0 interface..."
# If interface is up - restart it safely
wg-quick down wg0 2>/dev/null || true
wg-quick up wg0

# Run in foreground
tail -f /dev/null