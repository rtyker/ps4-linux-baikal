#!/usr/bin/env python3
"""
harness_gbe_compare_working.py — Compara o estado dos registradores hold/pulse
dos periféricos que FUNCIONAM (AHCI, xHCI, USB0, USB1) com o da GBE, pra
entender o mecanismo de release por analogia.

100% LEITURA — não escreve nada em lugar nenhum.

Base do comparativo: `bpcie_baikal_sata_phy_init()` em drivers/ps4/ps4-bpcie.c
(código que JÁ FUNCIONA no Linux hoje, AHCI/xHCI sobem normalmente) usa:
    AHCI  (non-shared): hold_offset = 44  (0x2C)  pulse_offset = 108 (0x6C)
    xHCI  (shared)    : hold_offset = 48  (0x30)  pulse_offset = 112 (0x70)
e a sequência é:  pulse=1 -> hold=1 -> pulse=0   (o hold FICA em 1, nunca zera)

Padrão observado: pulse = hold + 0x40, válido pros 4 periféricos conhecidos.
A GBE, segundo a tabela do RE do quiesce do Orbis (usada no commit revertido
d3fa7b72c), seria hold=0x20 / pulse=0x74 — o ÚNICO par que quebra o padrão
(0x20 + 0x40 = 0x60, não 0x74). Este script coleta dados pra decidir se
0x74 é erro de transcrição do RE e o par real é 0x20/0x60.

Também checa no dmesg se o caminho que funciona (`Baikal SATA PHY init`)
realmente rodou neste boot — isso diz se os valores lidos refletem um bloco
já liberado por software ou o estado natural pós-reset.
"""

import socket
import time
import re
import sqlite3
import datetime

PS4_IP = "192.168.6.128"
PS4_PORT = 23
DB_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db"

BPCIE_BASE = 0xc8980000

# (label, hold_offset, pulse_offset, origem/confiabilidade)
BLOCKS = [
    ("GBE",  0x20, 0x74, "RE quiesce Orbis (NAO confirmado; quebra o padrao +0x40)"),
    ("GBE?", 0x20, 0x60, "hipotese: par natural pelo padrao +0x40"),
    ("USB0", 0x24, 0x64, "RE quiesce Orbis (seque o padrao +0x40)"),
    ("USB1", 0x28, 0x68, "RE quiesce Orbis (seque o padrao +0x40)"),
    ("AHCI", 0x2c, 0x6c, "CONFIRMADO no codigo Linux que funciona"),
    ("xHCI", 0x30, 0x70, "CONFIRMADO no codigo Linux que funciona"),
]

VALUE_RE = re.compile(r'\b([0-9a-fA-F]{8})\b')


def read_until_prompt(s, prompt=b"~ # ", timeout=6):
    data = b""
    end_time = time.time() + timeout
    while time.time() < end_time:
        try:
            s.settimeout(0.5)
            chunk = s.recv(8192)
            if not chunk:
                break
            data += chunk
            if prompt in data:
                break
        except socket.timeout:
            pass
    return data


def run_cmd(s, cmd, wait=0.2):
    s.sendall(cmd.encode('ascii') + b"\n")
    time.sleep(wait)
    return read_until_prompt(s).decode('ascii', errors='replace')


def read_reg(s, addr):
    cmd = f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4"
    raw = run_cmd(s, cmd, wait=0.15).strip()
    m = VALUE_RE.search(raw)
    return m.group(1) if m else None


def log_reading(addr, label, block_label, value, notes):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO write_sweep_results
        (address, reg_name, block_label, value_before, value_written, value_after_immediate,
         value_after_settle, ping_ok, telnet_ok, ip_link_snapshot, result, timestamp, notes)
    VALUES (?, ?, 'COMPARE_WORKING', ?, NULL, NULL, NULL, 1, 1, NULL, 'READ_ONLY', ?, ?);
    """, (hex(addr), label, value, ts, f"{block_label}: {notes}"))
    conn.commit()
    conn.close()


def main():
    print("=" * 72)
    print("COMPARATIVO — hold/pulse dos periféricos que FUNCIONAM vs GBE (só leitura)")
    print("=" * 72)

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(6)
    s.connect((PS4_IP, PS4_PORT))
    read_until_prompt(s, timeout=3)
    print("Conectado.\n")

    # 1. O caminho que funciona rodou mesmo neste boot?
    print("--- dmesg: o caminho AHCI/xHCI que funciona rodou? ---")
    dmesg_sata = run_cmd(s, "dmesg | grep -i 'baikal sata\\|SATA PHY\\|EFUSE VALUE\\|Trace length' | head -20", wait=0.6)
    print(dmesg_sata.strip())
    print()

    print("--- dmesg: sky2/GBE ---")
    dmesg_sky2 = run_cmd(s, "dmesg | grep -i 'sky2\\|14\\.1' | head -20", wait=0.6)
    print(dmesg_sky2.strip())
    print()

    # 2. Estado dos registradores hold/pulse de cada bloco
    print("--- Registradores hold/pulse por bloco ---")
    print(f"{'bloco':6} {'hold addr':12} {'hold':10} {'pulse addr':12} {'pulse':10}  origem")
    print("-" * 100)

    results = {}
    for label, hold_off, pulse_off, origem in BLOCKS:
        hold_addr = BPCIE_BASE + hold_off
        pulse_addr = BPCIE_BASE + pulse_off
        hold_val = read_reg(s, hold_addr)
        pulse_val = read_reg(s, pulse_addr)
        results[label] = (hold_val, pulse_val)

        log_reading(hold_addr, f"{label}_HOLD", label, hold_val, f"hold offset {hex(hold_off)} | {origem}")
        log_reading(pulse_addr, f"{label}_PULSE", label, pulse_val, f"pulse offset {hex(pulse_off)} | {origem}")

        print(f"{label:6} {hex(hold_addr):12} {hold_val:10} {hex(pulse_addr):12} {pulse_val:10}  {origem}")

    print()

    # 3. Os periféricos que funcionam estão presentes/ativos?
    print("--- Dispositivos PCI presentes (Sony 104d) ---")
    lspci = run_cmd(s, "cat /proc/bus/pci/devices 2>/dev/null | awk '{print $1, $2}' | head -30", wait=0.5)
    print(lspci.strip())
    print()

    print("--- Discos/USB ativos (prova de que AHCI/xHCI funcionam) ---")
    blk = run_cmd(s, "ls /sys/class/block/ 2>/dev/null; echo '--- usb ---'; ls /sys/bus/usb/devices/ 2>/dev/null", wait=0.5)
    print(blk.strip())

    s.close()

    print("\n" + "=" * 72)
    print("ANÁLISE")
    print("=" * 72)
    gbe_hold, gbe_pulse_74 = results.get("GBE", (None, None))
    _, gbe_pulse_60 = results.get("GBE?", (None, None))
    ahci_hold, ahci_pulse = results.get("AHCI", (None, None))
    xhci_hold, xhci_pulse = results.get("xHCI", (None, None))

    print(f"AHCI (funciona): hold={ahci_hold} pulse={ahci_pulse}")
    print(f"xHCI (funciona): hold={xhci_hold} pulse={xhci_pulse}")
    print(f"GBE  (não func): hold={gbe_hold} pulse(0x74)={gbe_pulse_74} pulse(0x60)={gbe_pulse_60}")
    print()
    if ahci_hold == gbe_hold and ahci_pulse == gbe_pulse_74:
        print(">> GBE está no MESMO estado dos que funcionam — o bloqueio NÃO é este par de registradores.")
    else:
        print(">> GBE difere dos que funcionam — vale investigar o delta.")


if __name__ == "__main__":
    main()
