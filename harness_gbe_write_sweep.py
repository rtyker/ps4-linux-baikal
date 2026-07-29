#!/usr/bin/env python3
"""
harness_gbe_write_sweep.py — Varredura de ESCRITAS em blocos suspeitos do
southbridge Baikal (hold/pulse da GBE), ao vivo via telnet, DEPOIS do boot
completo (baseline 20260720-sky2len-fix). Cada escrita é feita UMA DE CADA
VEZ, com checagem de segurança (ping + telnet responsivo) logo em seguida —
se qualquer checagem falhar, o script para IMEDIATAMENTE e registra
exatamente em qual endereço parou, sem continuar a varredura às cegas.

Tudo grava em duas tabelas do SQLite:
  - write_sweep_results: uma linha por escrita (antes/depois, ping, telnet,
    resultado) — histórico bruto de cada tentativa.
  - hardware_registers: valores lidos (antes/depois) atualizados via
    mark_register_live_value, igual ao padrão dos outros harnesses.

Etapa 1 (leitura, sem risco): fecha o gap 0x180040-0x18007c da região BPCIE
glue (nunca lido antes) — cobre os offsets de "pulse" de USB0/USB1/AHCI/xHCI/
GBE do quiesce routine do Orbis.

Etapa 2 (escrita, risco real): hold->pulse->clear->clear no par específico da
GBE (0xc8980020 hold / 0xc8980074 pulse) — o MESMO par que o commit revertido
(d3fa7b72c) usava, mas feito aqui pós-boot via telnet em vez de no boot do
kernel (que travou/apagou vídeo duas vezes). Ainda não temos prova de que é
seguro pós-boot para ESTE par especificamente (só provamos isso pro par
0x10a030/34 hoje mais cedo) — por isso a checagem de segurança após cada
write.
"""

import socket
import subprocess
import time
import sys
import re
import sqlite3
import datetime

from mmio_write import build_write_cmd, parse_write_result

PS4_IP = "192.168.6.128"
PS4_PORT = 23

DB_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db"

BPCIE_BASE = 0xc8980000
GBE_HOLD_ADDR = 0xc8980020
GBE_PULSE_ADDR = 0xc8980074

VALUE_RE = re.compile(r'\b([0-9a-fA-F]{8})\b')


def get_db_connection():
    return sqlite3.connect(DB_PATH)


def create_test_record(phase, test_name, target, initial_action):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO test_history (timestamp, phase, test_name, target_component, action_taken, status, complementary_info)
    VALUES (?, ?, ?, ?, ?, 'PENDING', 'Inicializando sweep de escrita...');
    """, (ts, phase, test_name, target, initial_action))
    test_id = cur.lastrowid
    conn.commit()
    conn.close()
    return test_id


def update_test_progress(test_id, action, info, status="PENDING"):
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("""
    UPDATE test_history SET action_taken = ?, complementary_info = ?, status = ? WHERE id = ?;
    """, (action, info, status, test_id))
    conn.commit()
    conn.close()
    print(f"[{status}] {action} -> {info[:100]}")


def mark_register_live_value(name, addr, desc, bar_name, raw_val):
    conn = get_db_connection()
    cur = conn.cursor()
    m = VALUE_RE.search(raw_val)
    clean_val = m.group(1) if m else raw_val.strip()

    if addr >= 0xc9000000:
        offset = hex(addr - 0xc9000000)
    elif addr >= 0xc8800000:
        offset = hex(addr - 0xc8800000)
    else:
        offset = hex(addr)

    cur.execute("SELECT id FROM hardware_registers WHERE reg_name = ? OR (base_bar = ? AND reg_offset = ?);", (name, bar_name, offset))
    exists = cur.fetchone()
    if exists:
        cur.execute("UPDATE hardware_registers SET safe_to_read = 1, description = ? WHERE id = ?;",
                    (f"{desc} (Valor lido ao vivo: 0x{clean_val})", exists[0]))
    else:
        cur.execute("""INSERT INTO hardware_registers (device, base_bar, reg_offset, reg_name, description, safe_to_read, safe_to_write, risk_level)
        VALUES ('Baikal Hardware', ?, ?, ?, ?, 1, 0, 'SAFE');""",
                    (bar_name, offset, name, f"{desc} (Valor lido ao vivo: 0x{clean_val})"))
    conn.commit()
    conn.close()


def log_write_result(address, reg_name, block_label, value_before, value_written,
                      value_after_immediate, value_after_settle, ping_ok, telnet_ok,
                      ip_link_snapshot, result, notes=""):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO write_sweep_results
        (address, reg_name, block_label, value_before, value_written, value_after_immediate,
         value_after_settle, ping_ok, telnet_ok, ip_link_snapshot, result, timestamp, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    """, (hex(address), reg_name, block_label, value_before, value_written, value_after_immediate,
          value_after_settle, int(ping_ok), int(telnet_ok), ip_link_snapshot, result, ts, notes))
    conn.commit()
    conn.close()


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


def run_cmd(s, cmd, wait=0.2):
    s.sendall(cmd.encode('ascii') + b"\n")
    time.sleep(wait)
    return read_until_prompt(s).decode('ascii', errors='replace')


def read_reg(s, addr):
    cmd = f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4"
    raw = run_cmd(s, cmd, wait=0.15).strip()
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
        res = run_cmd(s, "echo alive", wait=0.3)
        return "alive" in res
    except Exception:
        return False


def connect_telnet():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect((PS4_IP, PS4_PORT))
    read_until_prompt(s, timeout=3)
    return s


def main():
    print("=" * 60)
    print("SWEEP DE ESCRITA — blocos suspeitos GBE (hold/pulse BPCIE)")
    print("=" * 60)

    test_id = create_test_record(
        "Fase 9", "Sweep leitura+escrita blocos suspeitos GBE",
        "BAR2 BPCIE Glue (0xc8980040-0xc898007c) + par hold/pulse GBE (0xc8980020/0xc8980074)",
        "Conectando ao Telnet"
    )

    try:
        s = connect_telnet()
        update_test_progress(test_id, "Conexão Telnet", "Conectado com sucesso na porta 23.")
    except Exception as e:
        update_test_progress(test_id, "Conexão Telnet", f"ERRO: {e}", status="FAIL_CONNECTION")
        print(f"ERRO DE CONEXÃO: {e}")
        sys.exit(1)

    # --- ETAPA 1: fechar gap de leitura 0x180040-0x18007c (sem risco) ---
    update_test_progress(test_id, "ETAPA 1: leitura do gap", "Lendo 0x180040-0x18007c (nunca lido antes)")
    gap_addrs = [BPCIE_BASE + off for off in range(0x40, 0x80, 4)]
    for addr in gap_addrs:
        val = read_reg(s, addr)
        name = f"BAR2_BPCIE_{hex(addr - BPCIE_BASE).upper().replace('0X', '0X')}"
        mark_register_live_value(name, addr, f"BAR2 BPCIE Glue Offset {hex(addr)}", "BAR2 (0xc8800000)", val or "READ_FAIL")
        print(f"  [{hex(addr)}] {name} = {val}")

    update_test_progress(test_id, "ETAPA 1 concluída", f"{len(gap_addrs)} endereços lidos e gravados em hardware_registers")

    # --- ETAPA 2: escrita hold->pulse->clear->clear no par GBE ---
    update_test_progress(test_id, "ETAPA 2: escrita GBE hold/pulse", f"Par hold={hex(GBE_HOLD_ADDR)} pulse={hex(GBE_PULSE_ADDR)}")

    hold_before = read_reg(s, GBE_HOLD_ADDR)
    pulse_before = read_reg(s, GBE_PULSE_ADDR)
    print(f"  ANTES: hold={hold_before} pulse={pulse_before}")

    write_steps = [
        (GBE_HOLD_ADDR, "00000001", "Passo 1: set hold"),
        (GBE_PULSE_ADDR, "00000001", "Passo 2: strobe pulse"),
        (GBE_PULSE_ADDR, "00000000", "Passo 3: clear pulse"),
        (GBE_HOLD_ADDR, "00000000", "Passo 4: release hold"),
    ]

    aborted = False
    for addr, val_hex, label in write_steps:
        value_before = read_reg(s, addr)
        # CORRIGIDO 2026-07-22: devmem NAO existe. printf octal + dd, verificado.
        cmd = build_write_cmd(addr, int(val_hex, 16))
        update_test_progress(test_id, label, f"Escrevendo 0x{val_hex} em {hex(addr)}")
        saida_w = run_cmd(s, cmd, wait=0.35)
        ok_w, det_w = parse_write_result(saida_w)
        if not ok_w:
            log_write_result(addr, None, "GBE hold/pulse BPCIE", value_before, val_hex,
                             None, None, True, True, None, "ESCRITA_FALHOU",
                             notes=f"{label} | {det_w}")
            update_test_progress(test_id, f"ESCRITA FALHOU: {label}",
                                 f"{hex(addr)}: {det_w}. A escrita NAO ocorreu.",
                                 status="FAIL_ESCRITA_NAO_OCORREU")
            print(f"!!! escrita nao ocorreu em {hex(addr)}: {det_w}")
            return
        time.sleep(0.15)

        value_after_immediate = read_reg(s, addr)

        ping_ok = check_ping()
        telnet_ok = check_telnet_alive(s)
        ip_link_snapshot = run_cmd(s, "ip link show", wait=0.3) if telnet_ok else "(telnet nao respondeu)"

        time.sleep(0.5)
        value_after_settle = read_reg(s, addr) if telnet_ok else None

        result = "OK"
        if not ping_ok or not telnet_ok:
            result = "CONNECTION_LOST"
        elif "eth0" in ip_link_snapshot:
            result = "ETH0_APPEARED"
        elif value_after_immediate != value_before:
            result = "VALUE_CHANGED"
        else:
            result = "NO_CHANGE"

        log_write_result(
            addr, None, "GBE hold/pulse BPCIE", value_before, val_hex,
            value_after_immediate, value_after_settle, ping_ok, telnet_ok,
            ip_link_snapshot, result, notes=label
        )

        update_test_progress(test_id, f"{label} -> resultado", f"ping={ping_ok} telnet={telnet_ok} result={result}")

        if not ping_ok or not telnet_ok:
            update_test_progress(
                test_id, "ABORTADO — perda de conexão", f"Parou em {label} ({hex(addr)}). ping_ok={ping_ok} telnet_ok={telnet_ok}",
                status="ABORTED_CONNECTION_LOST"
            )
            print(f"\n!!! ABORTADO em {label} ({hex(addr)}) — ping={ping_ok} telnet={telnet_ok} !!!")
            aborted = True
            break

    if not aborted:
        hold_after = read_reg(s, GBE_HOLD_ADDR)
        pulse_after = read_reg(s, GBE_PULSE_ADDR)
        chipid_after = read_reg(s, 0xc2000118)
        iplink_final = run_cmd(s, "ip link show", wait=0.3)

        mark_register_live_value("BAR2_BPCIE_GBE_HOLD", GBE_HOLD_ADDR, "BAR2 BPCIE GBE Hold (par com pulse 0x74)", "BAR2 (0xc8800000)", hold_after)
        mark_register_live_value("BAR2_BPCIE_GBE_PULSE", GBE_PULSE_ADDR, "BAR2 BPCIE GBE Pulse (par com hold 0x20)", "BAR2 (0xc8800000)", pulse_after)
        mark_register_live_value("B2_CHIP_ID", 0xc2000118, "BAR0 GBE Chip ID", "BAR0 (0xc2000000)", chipid_after or "READ_FAIL")

        summary = (
            f"hold: {hold_before} -> {hold_after}\n"
            f"pulse: {pulse_before} -> {pulse_after}\n"
            f"chipid pos-write: {chipid_after}\n"
            f"ip link final:\n{iplink_final.strip()}"
        )
        status_final = "OK_ETH0_ACTIVE" if "eth0" in iplink_final else "OK_SWEEP_SEM_ETH0"
        update_test_progress(test_id, "Sweep concluído", summary, status=status_final)
        print("\n" + "=" * 60)
        print(summary)
        print("=" * 60)
        s.close()
    else:
        print("Conexão perdida — verifique o console fisicamente (vídeo/ping) antes de qualquer nova tentativa.")

    print(f"\nTeste concluído (ID: {test_id})")


if __name__ == "__main__":
    main()
