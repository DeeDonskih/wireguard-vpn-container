# Wireguard docker container

## Setup and run
### Setup Docker (Ubuntu)
``` bash
sudo apt update
sudo apt upgrade --assume-yes # if required
sudo apt install docker.io    # Ubuntu 22.04
```

### Build Docker container
``` bash 
docker build -t my-wireguard .
```

### Run server
Docker run command:
``` bash
docker run -d \
  --name wireguard \                            # Container name
  --cap-add=NET_ADMIN \                         # Add capabilities
  --cap-add=SYS_MODULE \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv6.conf.all.disable_ipv6=0 \
  -e ENDPOINT="vpn.example.com" \               # Your server ip/hostname
  -e NETWORK="10.0.0.0/24" \                    # Internal tunnel network
  -e CLIENT_DEFAULT="mobile1" \                 # Create default user "mobile1"
  -p 51820:51820/udp \                          # Wireguard port forward
  -v $(pwd)/data:/data \                        # Accounts/settings mount point
  my-wireguard                                  # name of image 
```
or run:
``` bash
./run.sh
```

## Wireguard control
### Get clients list

``` bash
docker exec -it wireguard bash -lc '/usr/local/bin/wg-autosetup.sh --list'
```

### Show client URL/QR code
Get URL and QR for USERNAME config:
``` bash
docker exec -it wireguard bash -lc '/usr/local/bin/wg-autosetup.sh --show USERNAME'
```

### Add client
Add USERNAME account:
``` bash
docker exec -it wireguard bash -lc '/usr/local/bin/wg-autosetup.sh --add USERNAME'
```

### Delete client
Delete USERNAME account:
``` bash
docker exec -it wireguard bash -lc '/usr/local/bin/wg-autosetup.sh --del USERNAME'
```

### Restart
``` bash
docker exec -it wireguard bash -lc 'wg-quick down wg0 || true; wg-quick up wg0'
```