#!/usr/bin/env bash

usage() {
  echo "Usage: $0 {list|show|add|remove|restart} [username]"
  echo " $0 list          list of users"
  echo " $0 show <user>   show user URL and QR"
  echo " $0 add  <user>   add user"
  echo " $0 rm   <user>   remove user"
  echo " $0 restart       restart server"
}

list() {
    docker exec -it wireguard bash -lc '/usr/local/bin/wg-autosetup.sh --list'
}

show() {
  [ $# -lt 2 ] && { usage; exit 1; }
  for user in "${@:2}"; do
    docker exec -it wireguard bash -lc "/usr/local/bin/wg-autosetup.sh --show ${user}"
    echo "show ${user}"
  done
}

add() {
  [ $# -lt 2 ] && { usage; exit 1; }
  for user in "${@:2}"; do
    docker exec -it wireguard bash -lc "/usr/local/bin/wg-autosetup.sh --add ${user}"
    echo "add ${user}"
  done
}

remove() {
  [ $# -lt 2 ] && { usage; exit 1; }
  for user in "${@:2}"; do
    docker exec -it wireguard bash -lc "/usr/local/bin/wg-autosetup.sh --del ${user}"
    echo "remove ${user}"
  done
}

restart() {
  docker exec -it wireguard bash -lc "wg-quick down wg0 || true; wg-quick up wg0"
  echo "restart"
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

case "$1" in
    "list"|"ls")
        list
        ;;
    "show"|"user")
        show "$@"
        ;;
    "add")
        add "$@"
        ;;
    "remove"|"rm"|"del"|"delete")
        remove "$@"
        ;;
    "restart"|"reload")
        restart
        ;;
    *)
        usage
        exit 1
        ;;
esac

