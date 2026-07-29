#!/usr/bin/env python3
"""
harness_gbe_repeat_sequence.py — Repete a sequência COMPLETA
hold->pulse->clear->clear (par GBE 0xc8980020/0xc8980074) várias vezes
seguidas, lendo o Chip ID (0xc2000118) antes de cada ciclo e algumas vezes
logo depois, pra tentar reproduzir o "blip" (0x04/0x0d) visto antes e
descobrir se é esporádico/raro em vez de determinístico por passo (já
descartado no teste passo-a-passo anterior).

Checagem de segurança (ping + telnet) depois de cada ciclo completo,
abortando imediatamente se qualquer uma falhar. Uma linha por ciclo em
write_sweep_results (block_label='REPEAT_SEQUENCE').
"""

import socket
import subprocess
import time
import re
import sqlite3
import datetime
import sys

from mmio_write import build_write_cmd, parse_write_result

PS4_IP = "192.168.6.128"
PS4_PORT = 23
DB_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db"

GBE_HOLD_ADDR = 0xc8980020
GBE_PULSE_ADDR = 0xc8980074
ADDR_CHIPID = 0xc2000118

N_CYCLES = 8
N_CHIPID_READS_AFTER = 4
CHIPID_READ_DELAY = 0.12

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


def read_reg(s, addr, wait=0.12):
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


def log_cycle(iteration, chipid_before, chipid_after_readings, ping_ok, telnet_ok, result):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO write_sweep_results
        (address, reg_name, block_label, value_before, value_written, value_after_immediate,
         value_after_settle, ping_ok, telnet_ok, ip_link_snapshot, result, timestamp, notes)
    VALUES (?, NULL, 'REPEAT_SEQUENCE', ?, 'hold-pulse-clear-clear', ?, ?, ?, ?, NULL, ?, ?, ?);
    """, (hex(GBE_HOLD_ADDR), chipid_before, chipid_after_readings[0] if chipid_after_readings else None,
          chipid_after_readings[-1] if chipid_after_readings else None, int(ping_ok), int(telnet_ok),
          result, ts, f"iter={iteration} chipid_after_seq={chipid_after_readings}"))
    conn.commit()
    conn.close()


def main():
    print("=" * 60)
    print(f"REPETIÇÃO DA SEQUÊNCIA COMPLETA — {N_CYCLES}x, tentando isolar o blip do Chip ID")
    print("=" * 60)

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect((PS4_IP, PS4_PORT))
    read_until_prompt(s, timeout=3)
    print("Conectado.\n")

    blips_found = []

    for it in range(1, N_CYCLES + 1):
        chipid_before = read_reg(s, ADDR_CHIPID)

        # CORRIGIDO 2026-07-22: devmem NAO existe. printf octal + dd, verificado.
        for addr_w, val_w in [(GBE_HOLD_ADDR, 1), (GBE_PULSE_ADDR, 1),
                              (GBE_PULSE_ADDR, 0), (GBE_HOLD_ADDR, 0)]:
            saida_w = run_cmd(s, build_write_cmd(addr_w, val_w), wait=0.3)
            ok_w, det_w = parse_write_result(saida_w)
            if not ok_w:
                print(f"!!! escrita nao ocorreu em {hex(addr_w)}: {det_w} — abortando no ciclo {it}")
                sys.exit(1)

        chipid_after_readings = []
        for _ in range(N_CHIPID_READS_AFTER):
            val = read_reg(s, ADDR_CHIPID, wait=CHIPID_READ_DELAY)
            chipid_after_readings.append(val)

        ping_ok = check_ping()
        telnet_ok = check_telnet_alive(s)
        result = "CONNECTION_LOST" if (not ping_ok or not telnet_ok) else "OK"

        non_zero = [v for v in chipid_after_readings if v and v != "00000000"]
        if (chipid_before and chipid_before != "00000000") or non_zero:
            blips_found.append((it, chipid_before, chipid_after_readings))

        log_cycle(it, chipid_before, chipid_after_readings, ping_ok, telnet_ok, result)

        print(f"ciclo {it}: antes={chipid_before}  depois={chipid_after_readings}  ping={ping_ok} telnet={telnet_ok}")

        if not ping_ok or not telnet_ok:
            print(f"\n!!! ABORTADO no ciclo {it} !!!")
            sys.exit(1)

        time.sleep(0.3)

    s.close()

    print("\n" + "=" * 60)
    if blips_found:
        print(f"BLIP REPRODUZIDO em {len(blips_found)}/{N_CYCLES} ciclos:")
        for it, before, after in blips_found:
            print(f"  ciclo {it}: antes={before} depois={after}")
    else:
        print(f"NENHUM blip em {N_CYCLES} ciclos — Chip ID ficou 0x00000000 o tempo todo.")
    print("=" * 60)


if __name__ == "__main__":
    main()
