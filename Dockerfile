FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install WireGuard and utilities
RUN apt-get update && \
    apt-get install -y wireguard qrencode iproute2 iptables dnsutils nano vim curl ufw && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy our script
COPY wg-autosetup.sh /usr/local/bin/wg-autosetup.sh
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /usr/local/bin/wg-autosetup.sh /entrypoint.sh

# Data and config directories
VOLUME ["/data"]

WORKDIR /data

# Enable CAP_NET_ADMIN for WireGuard
# and expose UDP port 51820
EXPOSE 51820/udp

ENTRYPOINT ["/entrypoint.sh"]