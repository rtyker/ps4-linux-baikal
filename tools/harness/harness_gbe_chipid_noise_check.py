#!/usr/bin/env python3
"""
harness_gbe_chipid_noise_check.py — Confirma se o "Chip ID" da GBE
(BAR0 0xc2000118) é um valor estável ou está flutuando/ruído.

Não escreve NADA — só lê o mesmo endereço N vezes seguidas, sem nenhuma
escrita entre as leituras, e compara. Se o valor mudar sozinho sem
nenhuma ação nossa, é ruído/floating (leitura de um barramento sem clock,
não um registrador real). Se ficar estável, é um valor real.

Resultado gravado em write_sweep_results (result='NOISE_CHECK') pra
comparar com as leituras anteriores (0x04, 0x00, 0x0d) já vistas nos
testes de escrita anteriores.
"""

import socket
import time
import re
import sqlite3
import datetime

PS4_IP = "192.168.6.128"
PS4_PORT = 23
DB_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db"
ADDR_CHIPID = 0xc2000118
N_READS = 12
DELAY = 0.4

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


def read_reg(s, addr):
    cmd = f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4"
    raw = run_cmd(s, cmd).strip()
    m = VALUE_RE.search(raw)
    return m.group(1) if m else None


def log_result(readings):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    unique_vals = sorted(set(v for v in readings if v is not None))
    stable = len(unique_vals) <= 1
    result = "STABLE" if stable else "NOISE_FLOATING"
    notes = f"leituras={readings}"

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO write_sweep_results
        (address, reg_name, block_label, value_before, value_written, value_after_immediate,
         value_after_settle, ping_ok, telnet_ok, ip_link_snapshot, result, timestamp, notes)
    VALUES (?, ?, ?, ?, NULL, NULL, ?, 1, 1, NULL, ?, ?, ?);
    """, (hex(ADDR_CHIPID), "B2_CHIP_ID", "NOISE_CHECK", readings[0] if readings else None,
          readings[-1] if readings else None, result, ts, notes))
    conn.commit()
    conn.close()
    return stable, unique_vals


def main():
    print("=" * 60)
    print(f"CONFIRMAÇÃO DE RUÍDO — Chip ID GBE ({hex(ADDR_CHIPID)}), {N_READS} leituras, sem nenhum write")
    print("=" * 60)

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect((PS4_IP, PS4_PORT))
    read_until_prompt(s, timeout=3)
    print("Conectado.")

    readings = []
    for i in range(N_READS):
        val = read_reg(s, ADDR_CHIPID)
        readings.append(val)
        print(f"  leitura {i+1:2d}: {val}")
        time.sleep(DELAY)

    s.close()

    stable, unique_vals = log_result(readings)
    print("\n" + "=" * 60)
    if stable:
        print(f"RESULTADO: ESTÁVEL — todas as {N_READS} leituras deram {unique_vals[0] if unique_vals else 'N/A'}")
    else:
        print(f"RESULTADO: RUÍDO/FLOATING — valores distintos vistos: {unique_vals}")
    print("=" * 60)


if __name__ == "__main__":
    main()
