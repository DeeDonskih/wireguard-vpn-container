#!/usr/bin/env bash
# WireGuard auto-install for Ubuntu + QR + URL + list/del clients
# Usage:
#   sudo bash wg-autosetup.sh                       # install + create client 'mobile1'
#   sudo NETWORK=10.7.0.0/24 ENDPOINT=vpn.example.com bash wg-autosetup.sh
#   sudo bash wg-autosetup.sh --add phone_anna      # add client + show QR + URL
#   sudo bash wg-autosetup.sh --show phone_anna     # re-show QR + URL
#   sudo bash wg-autosetup.sh --list                # list clients
#   sudo bash wg-autosetup.sh --del phone_anna      # delete client

set -euo pipefail

WG_IF="wg0"
WG_DIR="/etc/wireguard"
CLIENT_DIR_DEFAULT="/root/wireguard-clients"
NETWORK="${NETWORK:-10.0.0.0/24}"
PORT="${PORT:-51820}"
IFACE="${IFACE:-}"
ENDPOINT="${ENDPOINT:-}"
DNS_VPN="${DNS_VPN:-1.1.1.1}"
CLIENT_DEFAULT="${CLIENT_DEFAULT:-mobile1}"

# Container?
IN_CONTAINER="${IN_CONTAINER:-}"
if [[ -z "$IN_CONTAINER" && -f "/.dockerenv" ]]; then IN_CONTAINER=1; fi

# Store clients in /data when in container
if [[ -n "${IN_CONTAINER}" ]]; then
  CLIENT_DIR="/data/wireguard-clients"
else
  CLIENT_DIR="${CLIENT_DIR_DEFAULT}"
fi

need_root() { [ "${EUID:-0}" -eq 0 ] || { echo "Run with sudo/root"; exit 1; }; }
need_ubuntu() { :; }  # Distribution check not critical in container

pkg_install() {
  # Packages are pre-installed in container image
  if [[ -n "${IN_CONTAINER}" ]]; then
    command -v wg >/dev/null || { echo "WireGuard not found in container"; exit 1; }
    command -v qrencode >/dev/null || { echo "qrencode not found"; exit 1; }
    return
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y wireguard qrencode iproute2 iptables dnsutils
  command -v ufw >/dev/null 2>&1 || apt-get install -y ufw || true
}

detect_iface() {
  if [[ -n "$IFACE" ]]; then echo "$IFACE"; return; fi
  local dev
  dev="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1 || true)"
  IFACE="${dev:-eth0}"
  echo "$IFACE"
}

detect_endpoint() {
  if [[ -n "$ENDPOINT" ]]; then echo "$ENDPOINT"; return; fi
  local ip
  # In container better pass external IP via ENV ENDPOINT,
  # but try to detect as fallback:
  ip="$( (command -v dig >/dev/null && dig +short myip.opendns.com @resolver1.opendns.com) || curl -fsS ifconfig.me || true )"
  ENDPOINT="${ip:-CHANGE_ME}"
  echo "$ENDPOINT"
}

enable_ip_forward() {
  # Outside container - configure sysctl
  if [[ -z "${IN_CONTAINER}" ]]; then
    sed -i 's/^#\?net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf || true
    sysctl -w net.ipv4.ip_forward=1 >/dev/null || true
  else
    echo "skip sysctl (container)"
  fi
}

ensure_keys() {
  umask 077
  mkdir -p "$WG_DIR" "$CLIENT_DIR"
  [[ -f "${WG_DIR}/server_private.key" ]] || wg genkey | tee "${WG_DIR}/server_private.key" | wg pubkey > "${WG_DIR}/server_public.key"
}

configure_server() {
  ensure_keys
  local iface endpoint
  iface="$(detect_iface)"
  endpoint="$(detect_endpoint)"

  if [[ ! -f "${WG_DIR}/${WG_IF}.conf" ]]; then
    cat > "${WG_DIR}/${WG_IF}.conf" <<EOF
[Interface]
Address = $(echo "$NETWORK" | awk -F/ '{print $1}' | awk -F. '{print $1"."$2"."$3".1" }')/24
ListenPort = ${PORT}
PrivateKey = $(cat "${WG_DIR}/server_private.key")

PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${iface} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${iface} -j MASQUERADE
EOF
  else
    sed -i "s/^ListenPort = .*/ListenPort = ${PORT}/" "${WG_DIR}/${WG_IF}.conf"
    sed -i "s/-o .* -j MASQUERADE/-o ${iface} -j MASQUERADE/" "${WG_DIR}/${WG_IF}.conf"
  fi

  # Outside container use UFW, inside container - skip
  if [[ -z "${IN_CONTAINER}" && $(command -v ufw >/dev/null 2>&1; echo $?) -eq 0 ]]; then
    ufw allow ${PORT}/udp || true
    sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw || true
    ufw reload || true
  fi

  # Bring up interface without systemd
  wg-quick down "${WG_IF}" 2>/dev/null || true
  wg-quick up "${WG_IF}"
  echo "WireGuard server started at ${endpoint}:${PORT}"
}

next_client_ip() {
  local base third used ip
  base="$(echo "$NETWORK" | cut -d/ -f1)"
  third="$(echo "$base" | awk -F. '{print $1"."$2"."$3}')"
  used="$(grep -E 'AllowedIPs\s*=\s*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/32' -o "${WG_DIR}/${WG_IF}.conf" 2>/dev/null | awk -F'[=/]' '{print $2}' | awk -F. '{print $4}' | sort -n | paste -sd, -)"
  for i in $(seq 2 254); do
    if [[ ",$used," != *",$i,"* ]]; then ip="${third}.${i}"; echo "$ip"; return; fi
  done
  echo "ERROR"; return 1
}

add_client() {
  local name="$1"
  [[ -n "$name" ]] || { echo "Client name not specified"; exit 1; }
  umask 077
  mkdir -p "$CLIENT_DIR"

  local c_priv c_pub s_pub ip endpoint
  c_priv="$(wg genkey)"
  c_pub="$(printf "%s" "$c_priv" | wg pubkey)"
  s_pub="$(cat "${WG_DIR}/server_public.key")"
  ip="$(next_client_ip)"
  endpoint="$(detect_endpoint)"

  # Add to server config
  cat >> "${WG_DIR}/${WG_IF}.conf" <<EOF

# ${name}
[Peer]
PublicKey = ${c_pub}
AllowedIPs = ${ip}/32
EOF

  # Client .conf
  cat > "${CLIENT_DIR}/${name}.conf" <<EOF
[Interface]
PrivateKey = ${c_priv}
Address = ${ip}/32
DNS = ${DNS_VPN}

[Peer]
PublicKey = ${s_pub}
Endpoint = ${endpoint}:${PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

  printf "%s\n" "${c_pub}" > "${CLIENT_DIR}/${name}.pub"

  # Apply if interface is up
  if ip link show "${WG_IF}" >/dev/null 2>&1; then
    wg set "${WG_IF}" peer "${c_pub}" allowed-ips "${ip}/32" 2>/dev/null || true
  fi

  echo "Client ${name} added: ${CLIENT_DIR}/${name}.conf"
}

_show_url_and_qr() {
  local file="$1"
  local url
  url="wireguard://$(base64 -w0 < "$file")"
  echo
  echo "=== Import URL ==="
  echo "${url}"
  echo "${url}" > "${file%.conf}.url"
  echo "URL saved to: ${file%.conf}.url"
}

show_qr() {
  local name="$1"
  [[ -f "${CLIENT_DIR}/${name}.conf" ]] || { echo "No ${CLIENT_DIR}/${name}.conf"; exit 1; }
  echo "=== QR for ${name} ==="
  qrencode -t ansiutf8 < "${CLIENT_DIR}/${name}.conf"
  _show_url_and_qr "${CLIENT_DIR}/${name}.conf"
  echo
  echo "File: ${CLIENT_DIR}/${name}.conf"
}

list_clients() {
  shopt -s nullglob
  local files=("${CLIENT_DIR}"/*.conf)
  if (( ${#files[@]} == 0 )); then
    echo "No clients."
    return
  fi
  printf "%-20s %-15s %-44s\n" "NAME" "IP" "PUBKEY"
  printf "%-20s %-15s %-44s\n" "--------------------" "---------------" "--------------------------------------------"
  for f in "${files[@]}"; do
    local name ip pub
    name="$(basename "$f" .conf)"
    ip="$(grep -E '^Address *= *' "$f" | head -n1 | awk -F'=' '{gsub(/ /,""); print $2}')"
    pub="$(cat "${CLIENT_DIR}/${name}.pub" 2>/dev/null || echo '-')"
    printf "%-20s %-15s %-44s\n" "$name" "$ip" "$pub"
  done
}

delete_client() {
  local name="$1"
  [[ -n "$name" ]] || { echo "Specify client name"; exit 1; }
  [[ -f "${WG_DIR}/${WG_IF}.conf" ]] || { echo "${WG_DIR}/${WG_IF}.conf not found"; exit 1; }

  local pub
  if [[ -f "${CLIENT_DIR}/${name}.pub" ]]; then
    pub="$(cat "${CLIENT_DIR}/${name}.pub")"
  else
    pub="$(awk -v n="$name" '
      BEGIN{found=0}
      $0 ~ "^# " n "$" {found=1; next}
      found && $0 ~ /^PublicKey *=/ {gsub(/ /,""); split($0,a,"="); print a[2]; exit}
    ' "${WG_DIR}/${WG_IF}.conf" 2>/dev/null || true)"
  fi

  # Remove from runtime if interface is up
  if [[ -n "${pub:-}" ]] && ip link show "${WG_IF}" >/dev/null 2>&1; then
    wg set "${WG_IF}" peer "${pub}" remove 2>/dev/null || true
  fi

  # Remove peer block from wg0.conf
  local tmp
  tmp="$(mktemp)"
  awk -v n="$name" '
    BEGIN{skip=0}
    {
      if ($0 ~ "^# " n "$") { skip=1; next }
      if (skip && $0 ~ /^\[Peer\]/) { next }
      if (skip && NF==0) { skip=0; next }
      if (!skip) print $0
    }
  ' "${WG_DIR}/${WG_IF}.conf" > "$tmp" || true

  mv "$tmp" "${WG_DIR}/${WG_IF}.conf"

  rm -f "${CLIENT_DIR}/${name}.conf" "${CLIENT_DIR}/${name}.url" "${CLIENT_DIR}/${name}.pub" 2>/dev/null || true
  echo "Client ${name} deleted."
}

main() {
  need_root
  pkg_install

  case "${1-}" in
    --add)   shift; add_client "${1:-}"; show_qr "${1:-}";;
    --show)  shift; show_qr "${1:-}";;
    --list)  list_clients;;
    --del|--delete|--remove) shift; delete_client "${1:-}";;
    *)
      enable_ip_forward
      configure_server
      if [[ ! -f "${CLIENT_DIR}/${CLIENT_DEFAULT}.conf" ]]; then
        add_client "${CLIENT_DEFAULT}"
      fi
      show_qr "${CLIENT_DEFAULT}"
      echo
      echo "Add:    sudo bash $0 --add <name>"
      echo "Show:   sudo bash $0 --show <name>"
      echo "List:   sudo bash $0 --list"
      echo "Delete: sudo bash $0 --del <name>"
      ;;
  esac
}
main "$@"