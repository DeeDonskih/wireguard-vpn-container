#!/usr/bin/env bash

docker run -d \
  --name wireguard \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv6.conf.all.disable_ipv6=0 \
  -e ENDPOINT="62.106.66.50" \
  -e NETWORK="10.0.0.0/24" \
  -e CLIENT_DEFAULT="mobile1" \
  -p 51820:51820/udp \
  -v $(pwd)/data:/data \
  my-wireguard
  