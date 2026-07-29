#!/usr/bin/env python3
"""
harness_gbe_bit10_isolado.py — Teste pontual: pulso ISOLADO do bit 10 (0x0400,
"GbE Clock Strobe") em BAR2+0x10a030/0x10a034, feito ao vivo via telnet
DEPOIS do boot completo (baseline 20260720-sky2len-fix), com todo passo
registrado no SQLite (test_history) e os registradores tocados atualizados em
hardware_registers — igual ao padrão do harness_gbe.py.

Diferença do Bloco 9 do harness_gbe.py: aquele pulso escrevia o valor
COMBINADO 0x000016c9 (bits 0,3,6,7,9,10,12 — vários blocos do southbridge de
uma vez). Este script escreve só 0x00000400 (bit 10 sozinho), isolando o
strobe da GBE dos outros periféricos, minimizando o blast radius.

NÃO faz nenhum unbind/bind de driver nem sondagem ICC — só o pulso em si e
leituras de antes/depois (BAR2 pulse/hold, BAR0 chip id da GBE).
"""

import socket
import time
import sys
import re
import sqlite3
import datetime

from mmio_write import build_write_cmd, parse_write_result

PS4_IP = "192.168.6.128"
PS4_PORT = 23

DB_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db"

ADDR_PULSE = 0xc890a030
ADDR_HOLD = 0xc890a034
ADDR_CHIPID = 0xc2000118
BIT10_MASK = 0x00000400


def get_db_connection():
    return sqlite3.connect(DB_PATH)


def create_test_record(phase, test_name, target, initial_action):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO test_history (timestamp, phase, test_name, target_component, action_taken, status, complementary_info)
    VALUES (?, ?, ?, ?, ?, 'PENDING', 'Inicializando teste de pulso isolado...');
    """, (ts, phase, test_name, target, initial_action))
    test_id = cur.lastrowid
    conn.commit()
    conn.close()
    return test_id


def update_test_progress(test_id, action, info, status="PENDING"):
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("""
    UPDATE test_history
    SET action_taken = ?, complementary_info = ?, status = ?
    WHERE id = ?;
    """, (action, info, status, test_id))
    conn.commit()
    conn.close()
    print(f"[{status}] {action} -> {info[:100]}")


def mark_register_live_value(name, addr, desc, bar_name, raw_val):
    conn = get_db_connection()
    cur = conn.cursor()

    hex_match = re.search(r'\b([0-9a-fA-F]{8})\b', raw_val)
    clean_val = hex_match.group(1) if hex_match else raw_val.strip()

    if addr >= 0xc9000000:
        offset = hex(addr - 0xc9000000)
    elif addr >= 0xc8800000:
        offset = hex(addr - 0xc8800000)
    else:
        offset = hex(addr)

    cur.execute("SELECT id FROM hardware_registers WHERE reg_name = ? OR (base_bar = ? AND reg_offset = ?);", (name, bar_name, offset))
    exists = cur.fetchone()
    if exists:
        cur.execute("""
        UPDATE hardware_registers
        SET safe_to_read = 1, description = ?
        WHERE id = ?;
        """, (f"{desc} (Valor lido ao vivo: 0x{clean_val})", exists[0]))
    else:
        cur.execute("""
        INSERT INTO hardware_registers (device, base_bar, reg_offset, reg_name, description, safe_to_read, safe_to_write, risk_level)
        VALUES ('Baikal Hardware', ?, ?, ?, ?, 1, 0, 'SAFE');
        """, (bar_name, offset, name, f"{desc} (Valor lido ao vivo: 0x{clean_val})"))
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


def run_cmd(s, test_id, cmd, action_name, wait=0.2):
    update_test_progress(test_id, f"ENVIANDO: {action_name}", f"Executando {cmd}")
    s.sendall(cmd.encode('ascii') + b"\n")
    time.sleep(wait)
    res = read_until_prompt(s).decode('ascii', errors='replace')
    update_test_progress(test_id, f"CONCLUÍDO: {action_name}", res.strip())
    return res


def read_reg(s, test_id, addr, label):
    cmd = f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4"
    val = run_cmd(s, test_id, cmd, f"Ler {label} ({hex(addr)})", wait=0.15).strip()
    return val


def main():
    print("=" * 60)
    print("PULSO ISOLADO BIT 10 (0x0400 GbE Clock Strobe) — pós-boot, sky2len-fix")
    print("=" * 60)

    test_id = create_test_record(
        "Fase 8", "Pulso Isolado Bit10 GBE (0x0400) em BAR2+0x10a030/34",
        "BAR2 Pervasive Clock (0xc890a030/0xc890a034) + BAR0 GBE ChipID (0xc2000118)",
        "Conectando ao Telnet"
    )

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect((PS4_IP, PS4_PORT))
        read_until_prompt(s, timeout=3)
        update_test_progress(test_id, "Conexão Telnet", "Conectado com sucesso na porta 23.")
    except Exception as e:
        err_msg = f"ERRO DE CONEXÃO: {e}"
        update_test_progress(test_id, "Conexão Telnet", err_msg, status="FAIL_CONNECTION")
        print(err_msg)
        sys.exit(1)

    # --- Estado ANTES ---
    pulse_before = read_reg(s, test_id, ADDR_PULSE, "BAR2_CLOCK_PULSE (antes)")
    hold_before = read_reg(s, test_id, ADDR_HOLD, "BAR2_CLOCK_HOLD (antes)")
    chipid_before = read_reg(s, test_id, ADDR_CHIPID, "GBE ChipID (antes)")

    mark_register_live_value("BAR2_CLOCK_PULSE", ADDR_PULSE, "BAR2 Pervasive Clock Pulse/Strobe", "BAR2 (0xc8800000)", pulse_before)
    mark_register_live_value("BAR2_CLOCK_HOLD", ADDR_HOLD, "BAR2 Pervasive Clock Hold Mask", "BAR2 (0xc8800000)", hold_before)
    mark_register_live_value("B2_CHIP_ID", ADDR_CHIPID, "BAR0 GBE Chip ID", "BAR0 (0xc2000000)", chipid_before)

    # --- Pulso isolado: só o bit 10 (0x0400), não o valor combinado 0x16c9 ---
    update_test_progress(test_id, "PULSO BIT10 ISOLADO", "Iniciando sequência hold->strobe->clear só com 0x00000400")

    # CORRIGIDO 2026-07-22: devmem NAO existe (exit 127). printf octal + dd,
    # com verificacao — aborta se a escrita nao for confirmada.
    for addr_w, val_w, label_w in [
        (ADDR_HOLD,  BIT10_MASK, "Passo 1: Hold Mask bit10"),
        (ADDR_PULSE, BIT10_MASK, "Passo 2: Strobe bit10 isolado"),
        (ADDR_PULSE, 0x00000000, "Passo 3: Clear pulse"),
        (ADDR_HOLD,  0x00000000, "Passo 4: Release hold"),
    ]:
        saida_w = run_cmd(s, test_id, build_write_cmd(addr_w, val_w), label_w)
        ok_w, det_w = parse_write_result(saida_w)
        if not ok_w:
            update_test_progress(test_id, f"ESCRITA FALHOU: {label_w}",
                                 f"{hex(addr_w)}: {det_w}. A escrita NAO ocorreu.",
                                 status="FAIL_ESCRITA_NAO_OCORREU")
            print(f"!!! escrita nao ocorreu em {hex(addr_w)}: {det_w}")
            s.close()
            return
        update_test_progress(test_id, f"escrita confirmada: {label_w}", det_w)
        time.sleep(0.12)
    time.sleep(0.2)

    # --- Estado DEPOIS ---
    pulse_after = read_reg(s, test_id, ADDR_PULSE, "BAR2_CLOCK_PULSE (depois)")
    hold_after = read_reg(s, test_id, ADDR_HOLD, "BAR2_CLOCK_HOLD (depois)")
    chipid_after = read_reg(s, test_id, ADDR_CHIPID, "GBE ChipID (depois)")

    iplink = run_cmd(s, test_id, "ip link show", "Checagem ip link pós-pulso")

    mark_register_live_value("BAR2_CLOCK_PULSE", ADDR_PULSE, "BAR2 Pervasive Clock Pulse/Strobe", "BAR2 (0xc8800000)", pulse_after)
    mark_register_live_value("BAR2_CLOCK_HOLD", ADDR_HOLD, "BAR2 Pervasive Clock Hold Mask", "BAR2 (0xc8800000)", hold_after)
    mark_register_live_value("B2_CHIP_ID", ADDR_CHIPID, "BAR0 GBE Chip ID", "BAR0 (0xc2000000)", chipid_after)

    summary = (
        f"ANTES: pulse={pulse_before} hold={hold_before} chipid={chipid_before}\n"
        f"DEPOIS: pulse={pulse_after} hold={hold_after} chipid={chipid_after}\n"
        f"ip link:\n{iplink.strip()}"
    )
    status_final = "OK_ETH0_ACTIVE" if "eth0" in iplink else "OK_PULSE_SEM_MUDANCA_CHIPID"
    update_test_progress(test_id, "Pulso isolado concluído", summary, status=status_final)
    s.close()

    print("\n" + "=" * 60)
    print(summary)
    print("=" * 60)
    print(f"Teste concluído (ID: {test_id}, STATUS: {status_final})")


if __name__ == "__main__":
    main()
