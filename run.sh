#!/usr/bin/env bash

get_external_ip() {
    curl -fsS ifconfig.me
}

if [ -z "${SERVER_HOSTNAME}" ]; then
    SERVER_HOSTNAME=$(get_external_ip)
fi

docker run -d \
  --name wireguard \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv6.conf.all.disable_ipv6=0 \
  -e ENDPOINT="${SERVER_HOSTNAME}" \
  -e NETWORK="10.0.0.0/24" \
  -e CLIENT_DEFAULT="mobile1" \
  -p 51820:51820/udp \
  -v $(pwd)/data:/data \
  my-wireguard
  