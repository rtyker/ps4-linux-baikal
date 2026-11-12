#!/usr/bin/env python3
"""
netconsole_listener.py — Receptor UDP de logs em tempo real do Kernel Linux do PS4.

Uso:
    python3 scripts/netconsole_listener.py [PORTA] [ARQUIVO_LOG]

Exemplo:
    python3 scripts/netconsole_listener.py 6666 ps4_netconsole.log
"""

import sys
import socket
import datetime

port = int(sys.argv[1]) if len(sys.argv) > 1 else 6666
log_file = sys.argv[2] if len(sys.argv) > 2 else "netconsole_ps4.log"

print(f"=== PS4 Netconsole Receiver ===")
print(f"Escutando porta UDP {port}...")
print(f"Salvando logs em: {log_file}")
print("Pressione Ctrl+C para sair.\n")

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("0.0.0.0", port))

f = open(log_file, "a", encoding="utf-8", errors="ignore")

try:
    while True:
        data, addr = sock.recvfrom(4096)
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        text = data.decode("utf-8", errors="ignore")
        line = f"[{timestamp}] [{addr[0]}:{addr[1]}] {text}"
        print(line, end="")
        f.write(line)
        f.flush()
except KeyboardInterrupt:
    print("\nReceptor encerrado.")
finally:
    f.close()
    sock.close()
