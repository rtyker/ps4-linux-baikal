#!/usr/bin/env python3
"""
harness_gbe_step_by_step.py — Repete a sequência hold->pulse->clear->clear no
par GBE (0xc8980020 hold / 0xc8980074 pulse), mas dessa vez lê o Chip ID
(0xc2000118) VÁRIAS VEZES rapidamente logo após CADA um dos 4 passos, pra
flagrar exatamente em qual passo aparece o "blip" (visto antes como 0x04/0x0d)
e quanto tempo ele demora pra cair de volta a 0x00000000 (já confirmado
estável/sem ruído em repouso).

Mesma checagem de segurança (ping + telnet) depois de cada passo, abortando
imediatamente se qualquer uma falhar. Resultado gravado em
write_sweep_results, uma linha por passo, com a sequência de leituras do
chip id na coluna notes.
"""

import socket
import subprocess
import time
import re
import sqlite3
import datetime

from mmio_write import build_write_cmd, parse_write_result

PS4_IP = "192.168.6.128"
PS4_PORT = 23
DB_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db"

GBE_HOLD_ADDR = 0xc8980020
GBE_PULSE_ADDR = 0xc8980074
ADDR_CHIPID = 0xc2000118

N_CHIPID_READS = 6
CHIPID_READ_DELAY = 0.15

VALUE_RE = re.compile(r'\b([0-9a-fA-F]{8})\b')


def read_until_prompt(s, prompt=b"~ # ", timeout=5):
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


def run_cmd(s, cmd, wait=0.15):
    s.sendall(cmd.encode('ascii') + b"\n")
    time.sleep(wait)
    return read_until_prompt(s).decode('ascii', errors='replace')


def read_reg(s, addr, wait=0.15):
    cmd = f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4"
    raw = run_cmd(s, cmd, wait=wait).strip()
    m = VALUE_RE.search(raw)
    return m.group(1) if m else None


def check_ping():
    try:
        res = subprocess.run(["ping", "-c", "1", "-W", "2", PS4_IP], capture_output=True, timeout=5)
        return res.returncode == 0
    except Exception:
        return False


def check_telnet_alive(s):
    try:
        return "alive" in run_cmd(s, "echo alive", wait=0.3)
    except Exception:
        return False


def log_step(addr, label, value_written, chipid_readings, ping_ok, telnet_ok, result):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO write_sweep_results
        (address, reg_name, block_label, value_before, value_written, value_after_immediate,
         value_after_settle, ping_ok, telnet_ok, ip_link_snapshot, result, timestamp, notes)
    VALUES (?, NULL, 'CHIPID_STEP_BY_STEP', NULL, ?, ?, ?, ?, ?, NULL, ?, ?, ?);
    """, (hex(addr), value_written, chipid_readings[0] if chipid_readings else None,
          chipid_readings[-1] if chipid_readings else None, int(ping_ok), int(telnet_ok),
          result, ts, f"{label}: chipid_seq={chipid_readings}"))
    conn.commit()
    conn.close()


def main():
    print("=" * 60)
    print("TESTE PASSO A PASSO — blip do Chip ID após cada passo hold/pulse GBE")
    print("=" * 60)

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect((PS4_IP, PS4_PORT))
    read_until_prompt(s, timeout=3)
    print("Conectado.\n")

    steps = [
        (GBE_HOLD_ADDR, "00000001", "Passo 1: set hold"),
        (GBE_PULSE_ADDR, "00000001", "Passo 2: strobe pulse"),
        (GBE_PULSE_ADDR, "00000000", "Passo 3: clear pulse"),
        (GBE_HOLD_ADDR, "00000000", "Passo 4: release hold"),
    ]

    for addr, val_hex, label in steps:
        print(f"{label} -> escrevendo 0x{val_hex} em {hex(addr)}")
        saida_w = run_cmd(s, build_write_cmd(addr, int(val_hex, 16)), wait=0.35)
        ok_w, det_w = parse_write_result(saida_w)
        if not ok_w:
            log_step(addr, label, val_hex, [], True, True, "ESCRITA_FALHOU")
            print(f"!!! escrita nao ocorreu em {hex(addr)}: {det_w} — abortando")
            return

        chipid_readings = []
        for i in range(N_CHIPID_READS):
            val = read_reg(s, ADDR_CHIPID, wait=CHIPID_READ_DELAY)
            chipid_readings.append(val)
            print(f"    chipid t+{i*CHIPID_READ_DELAY:.2f}s: {val}")

        ping_ok = check_ping()
        telnet_ok = check_telnet_alive(s)
        result = "CONNECTION_LOST" if (not ping_ok or not telnet_ok) else "OK"

        log_step(addr, label, val_hex, chipid_readings, ping_ok, telnet_ok, result)
        print(f"    ping={ping_ok} telnet={telnet_ok}\n")

        if not ping_ok or not telnet_ok:
            print(f"!!! ABORTADO em {label} !!!")
            return

    s.close()
    print("=" * 60)
    print("Teste passo a passo concluído — ver write_sweep_results (block_label='CHIPID_STEP_BY_STEP')")
    print("=" * 60)


if __name__ == "__main__":
    main()
