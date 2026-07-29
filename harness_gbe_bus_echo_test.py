#!/usr/bin/env python3
"""
harness_gbe_bus_echo_test.py — Testa se a BAR0 da GBE está FLUTUANDO
(devolvendo resíduo do último ciclo do barramento) em vez de responder com
conteúdo real de registrador.

100% LEITURA — não escreve nada.

Hipótese (levantada 2026-07-22 na variante A do harness_gbe_correct_sequence):
logo após escrever 0x00000001 no pulse (0xc8980074), a leitura do dword em
0xc2000118 devolveu exatamente 0x00000001. Se a BAR0 do MAC estivesse
apenas "morta lendo zeros", isso não deveria acontecer. Um alvo MMIO sem
alimentação/clock costuma não drivar o barramento, e o host lê o valor
residual do ciclo anterior (capacitância do barramento).

Método: intercalar leituras de registradores CONHECIDOS e com valores
DISTINTOS entre si com leituras da BAR0 da GBE. Se a GBE devolver (total ou
parcialmente) o valor lido imediatamente antes, está ecoando o barramento —
prova de que o MAC não responde de verdade, e que TODA leitura de BAR0 da
GBE feita até hoje é lixo, não estado real.

Registradores-isca (todos já validados como safe_to_read no SQLite):
  0xc900c06c = 0xbfbf8787  (efuse trim compartilhado)
  0xc900c060 = 0x0d13b1a2  (efuse)
  0xc900c064 = 0x492ce89d  (efuse)
  0xc890a030 = 0x000016c9  (pervasive clock pulse)

Resultado gravado em test_history (Fase 11) e write_sweep_results
(block_label='BUS_ECHO_TEST').
"""

import socket
import time
import re
import sqlite3
import datetime
import sys

PS4_IP = "192.168.6.128"
PS4_PORT = 23
DB_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db"

ADDR_GBE = 0xc2000118  # BAR0 da GBE (dword que cobre CONN_TYP..CHIP_ID)

# (endereço, valor esperado conhecido, rótulo)
BAIT_REGS = [
    (0xc900c06c, "bfbf8787", "efuse trim compartilhado"),
    (0xc900c060, "0d13b1a2", "efuse 0x60"),
    (0xc900c064, "492ce89d", "efuse 0x64"),
    (0xc890a030, "000016c9", "pervasive clock pulse"),
]

DWORD_RE = re.compile(r'\b([0-9a-fA-F]{8})\b')


def create_test_record(phase, test_name, target, initial_action):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO test_history (timestamp, phase, test_name, target_component, action_taken, status, complementary_info)
    VALUES (?, ?, ?, ?, ?, 'PENDING', 'Inicializando teste de eco de barramento...');
    """, (ts, phase, test_name, target, initial_action))
    tid = cur.lastrowid
    conn.commit()
    conn.close()
    return tid


def update_test_progress(test_id, action, info, status="PENDING"):
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("UPDATE test_history SET action_taken=?, complementary_info=?, status=? WHERE id=?;",
                (action, info, status, test_id))
    conn.commit()
    conn.close()
    print(f"[{status}] {action} -> {info[:110]}")


def log_pair(bait_addr, bait_val, gbe_val, echoed, notes):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO write_sweep_results
        (address, reg_name, block_label, value_before, value_written, value_after_immediate,
         value_after_settle, ping_ok, telnet_ok, ip_link_snapshot, result, timestamp, notes)
    VALUES (?, 'B2_CONN_TYP_dword', 'BUS_ECHO_TEST', ?, NULL, ?, NULL, 1, 1, NULL, ?, ?, ?);
    """, (hex(ADDR_GBE), bait_val, gbe_val, "ECHOED" if echoed else "NOT_ECHOED", ts,
          f"isca={hex(bait_addr)} valor_isca={bait_val} gbe_leu={gbe_val} | {notes}"))
    conn.commit()
    conn.close()


def read_until_prompt(s, prompt=b"~ # ", timeout=6):
    data = b""
    end = time.time() + timeout
    while time.time() < end:
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


def run_cmd(s, cmd, wait=0.18):
    s.sendall(cmd.encode('ascii') + b"\n")
    time.sleep(wait)
    return read_until_prompt(s).decode('ascii', errors='replace')


def read_dword(s, addr):
    raw = run_cmd(s, f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4")
    m = DWORD_RE.search(raw)
    return m.group(1) if m else None


def read_pair_same_shell(s, bait_addr):
    """Lê isca e GBE no MESMO comando, para o ciclo de barramento da GBE vir
    imediatamente depois do da isca, sem nada no meio."""
    cmd = (f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(bait_addr)} / 4 )) 2>/dev/null | od -An -tx4; "
           f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(ADDR_GBE)} / 4 )) 2>/dev/null | od -An -tx4")
    raw = run_cmd(s, cmd, wait=0.35)
    vals = DWORD_RE.findall(raw)
    if len(vals) >= 2:
        return vals[0], vals[1]
    return (vals[0] if vals else None), None


def main():
    print("=" * 74)
    print("TESTE DE ECO DE BARRAMENTO — a BAR0 da GBE responde ou está flutuando?")
    print("=" * 74)

    test_id = create_test_record(
        "Fase 11",
        "Teste de eco de barramento na BAR0 da GBE",
        f"GBE BAR0 {hex(ADDR_GBE)} vs registradores-isca BAR4/BAR2",
        "Conectando ao Telnet"
    )

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(6)
        s.connect((PS4_IP, PS4_PORT))
        read_until_prompt(s, timeout=3)
        update_test_progress(test_id, "Conexão Telnet", "Conectado na porta 23.")
    except Exception as e:
        update_test_progress(test_id, "Conexão Telnet", f"ERRO: {e}", status="FAIL_CONNECTION")
        print(f"ERRO: {e}")
        sys.exit(1)

    print(f"\n{'isca':14} {'esperado':10} {'isca leu':10} {'GBE leu':10} veredito")
    print("-" * 66)

    echo_count = 0
    total = 0

    for bait_addr, expected, label in BAIT_REGS:
        for rep in range(2):
            bait_val, gbe_val = read_pair_same_shell(s, bait_addr)
            total += 1
            echoed = bool(bait_val and gbe_val and bait_val == gbe_val and gbe_val != "00000000")
            if echoed:
                echo_count += 1
            verdict = "ECO!" if echoed else ("zeros" if gbe_val == "00000000" else "difere")
            print(f"{hex(bait_addr):14} {expected:10} {str(bait_val):10} {str(gbe_val):10} {verdict}")
            log_pair(bait_addr, bait_val, gbe_val, echoed, f"{label} rep{rep+1}")
            time.sleep(0.15)

    s.close()

    print("\n" + "=" * 74)
    if echo_count > 0:
        conclusao = (f"BARRAMENTO FLUTUANTE CONFIRMADO — a GBE ecoou o valor da isca em "
                     f"{echo_count}/{total} leituras. Toda leitura de BAR0 da GBE é lixo residual, "
                     f"não estado real do MAC.")
        status = "CONFIRMED_FLOATING_BUS"
    else:
        conclusao = (f"SEM ECO em {total} leituras — a GBE devolveu 0x00000000 de forma consistente "
                     f"mesmo logo após ciclos com valores distintos no barramento. O alvo responde "
                     f"com zeros de verdade (não é barramento flutuante).")
        status = "NO_ECHO_REAL_ZEROS"
    print(conclusao)
    print("=" * 74)

    update_test_progress(test_id, "Teste de eco concluído", conclusao, status=status)


if __name__ == "__main__":
    main()
