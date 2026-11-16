#!/usr/bin/env python3
"""
capture_dmesg.py — Captura o dmesg (inclui as mensagens "DEBUG LOOP" que aparecem
na TV) via telnet e salva em um arquivo .txt local para análise offline.

Uso:
    python3 capture_dmesg.py [ip] [porta]

Padrão: ip=192.168.6.128, porta=23 (mesmos valores do harness_gbe.py).
"""

import socket
import sys
import time

DEFAULT_IP = "192.168.6.128"
DEFAULT_PORT = 23

PROMPT = b"~ # "
CMD = "dmesg"


def read_until_prompt(s, prompt=PROMPT, timeout=8):
    data = b""
    end_time = time.time() + timeout
    while time.time() < end_time:
        try:
            s.settimeout(0.5)
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
            if prompt in data:
                break
        except socket.timeout:
            pass
    return data


def main():
    ip = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_IP
    port = int(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_PORT

    print(f"Conectando em {ip}:{port}...")
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect((ip, port))
    read_until_prompt(s, timeout=3)  # descarta banner/prompt inicial

    print(f"Executando '{CMD}'...")
    s.sendall(CMD.encode("ascii") + b"\n")
    time.sleep(1.0)
    raw = read_until_prompt(s, timeout=10)
    s.close()

    text = raw.decode("ascii", errors="replace")

    out_path = "dmesg.log"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text)

    print(f"Salvo em: {out_path} ({len(text)} bytes)")


if __name__ == "__main__":
    main()
