#!/bin/bash
# Colocar em /root/http_log_server.sh no rootfs do PS4
# Acessar do PC: curl http://192.168.6.130:8080/dmesg
while true; do
  {
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n"
    dmesg
  } | nc -l -p 8080 -q 1 2>/dev/null
done
