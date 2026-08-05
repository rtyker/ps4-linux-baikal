#!/usr/bin/env python3
"""
harness_gbe_correct_sequence.py — Aplica na GBE a sequência EXATA do código
que comprovadamente funciona (AHCI/xHCI), testando os dois candidatos de
offset de pulse. Tudo registrado no SQLite (test_history + write_sweep_results).

Base (drivers/ps4/ps4-bpcie.c, bpcie_baikal_sata_phy_init — roda no boot e
funciona, confirmado no dmesg ao vivo):

    glue_write32(pulse_offset, 1);
    glue_write32(hold_offset,  1);
    glue_write32(pulse_offset, 0);
    /* hold FICA em 1 — NÃO existe quarta escrita */

Diferenças em relação a tudo que já testamos nesta sessão:
  - ordem correta (pulse ANTES do hold; antes fazíamos hold primeiro)
  - SEM o quarto passo `hold=0` (o commit revertido d3fa7b72c o adicionou por
    conta própria, e nossos testes via telnet também)

Variantes testadas (hold sempre 0x20):
  A) pulse = 0x74  — offset da tabela do RE do quiesce do Orbis
  B) pulse = 0x60  — par natural pelo padrão pulse = hold + 0x40, que vale
                     para USB0/USB1/AHCI/xHCI (0x24/0x64, 0x28/0x68,
                     0x2c/0x6c, 0x30/0x70)

VERIFICAÇÃO (nunca por readback do hold/pulse — eles são write-only e leem
sempre 0, provado em 2026-07-22):
  - B2_CHIP_ID no endereço CERTO: 0xc200011b (1 byte). Antes líamos o dword
    em 0xc2000118, que é B2_CONN_TYP; o chip id é o byte mais alto.
  - rebind do sky2 + dmesg (a mensagem "unsupported chip type 0xNN" mostra
    exatamente que valor o driver leu).

Segurança: ping + telnet conferidos após cada escrita; aborta na hora se
qualquer um falhar.
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

BPCIE_BASE = 0xc8980000
GBE_HOLD_OFF = 0x20

ADDR_CHIPID_BYTE = 0xc200011b   # B2_CHIP_ID (1 byte) — o endereço CERTO
ADDR_CONNTYP_DWORD = 0xc2000118  # dword que cobre CONN_TYP/PMD_TYP/MAC_CFG/CHIP_ID

PCI_ID = "0000:00:14.1"

VARIANTS = [
    ("A", 0x74, "offset da tabela do RE do quiesce Orbis"),
    ("B", 0x60, "par natural pelo padrao pulse = hold + 0x40"),
]

DWORD_RE = re.compile(r'\b([0-9a-fA-F]{8})\b')
BYTE_RE = re.compile(r'\b([0-9a-fA-F]{2})\b')


# ---------- SQLite ----------

def create_test_record(phase, test_name, target, initial_action):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO test_history (timestamp, phase, test_name, target_component, action_taken, status, complementary_info)
    VALUES (?, ?, ?, ?, ?, 'PENDING', 'Inicializando sequencia correta...');
    """, (ts, phase, test_name, target, initial_action))
    test_id = cur.lastrowid
    conn.commit()
    conn.close()
    return test_id


def update_test_progress(test_id, action, info, status="PENDING"):
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("UPDATE test_history SET action_taken=?, complementary_info=?, status=? WHERE id=?;",
                (action, info, status, test_id))
    conn.commit()
    conn.close()
    print(f"[{status}] {action} -> {info[:110]}")


def log_sweep(address, reg_name, block_label, value_before, value_written,
              value_after_immediate, value_after_settle, ping_ok, telnet_ok,
              ip_link_snapshot, result, notes):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO write_sweep_results
        (address, reg_name, block_label, value_before, value_written, value_after_immediate,
         value_after_settle, ping_ok, telnet_ok, ip_link_snapshot, result, timestamp, notes)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    """, (hex(address), reg_name, block_label, value_before, value_written,
          value_after_immediate, value_after_settle, int(ping_ok), int(telnet_ok),
          ip_link_snapshot, result, ts, notes))
    conn.commit()
    conn.close()


# ---------- Telnet ----------

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


def read_chipid_byte(s):
    """B2_CHIP_ID = 0x11b, registrador de 1 byte."""
    raw = run_cmd(s, f"dd if=/dev/mem bs=1 count=1 skip=$(( {hex(ADDR_CHIPID_BYTE)} )) 2>/dev/null | od -An -tx1", wait=0.2)
    lines = [l for l in raw.splitlines() if l.strip() and 'dd if=' not in l and '~ #' not in l]
    for line in lines:
        m = BYTE_RE.search(line)
        if m:
            return m.group(1)
    return None


def read_conntyp_dword(s):
    raw = run_cmd(s, f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(ADDR_CONNTYP_DWORD)} / 4 )) 2>/dev/null | od -An -tx4", wait=0.2)
    m = DWORD_RE.search(raw)
    return m.group(1) if m else None


def check_ping():
    try:
        return subprocess.run(["ping", "-c", "1", "-W", "2", PS4_IP],
                              capture_output=True, timeout=5).returncode == 0
    except Exception:
        return False


def check_telnet_alive(s):
    try:
        return "alive" in run_cmd(s, "echo alive", wait=0.3)
    except Exception:
        return False


# ---------- Teste ----------

def run_variant(s, test_id, variant, pulse_off, origem):
    hold_addr = BPCIE_BASE + GBE_HOLD_OFF
    pulse_addr = BPCIE_BASE + pulse_off
    block_label = f"CORRECT_SEQ_VAR_{variant}"

    update_test_progress(test_id, f"VARIANTE {variant}",
                         f"hold={hex(hold_addr)} pulse={hex(pulse_addr)} ({origem})")

    chipid_before = read_chipid_byte(s)
    conntyp_before = read_conntyp_dword(s)
    print(f"  ANTES: B2_CHIP_ID(0x11b)={chipid_before}  dword(0x118)={conntyp_before}")

    # Sequência EXATA do código que funciona — sem quarto passo
    steps = [
        (pulse_addr, "00000001", "1/3 pulse=1"),
        (hold_addr,  "00000001", "2/3 hold=1"),
        (pulse_addr, "00000000", "3/3 pulse=0 (hold FICA em 1)"),
    ]

    for addr, val, label in steps:
        print(f"  {label}: escrevendo 0x{val} em {hex(addr)}")
        saida_w = run_cmd(s, build_write_cmd(addr, int(val, 16)), wait=0.35)
        ok_w, det_w = parse_write_result(saida_w)
        if not ok_w:
            log_sweep(addr, None, block_label, None, val, None, None, True, True,
                      None, "ESCRITA_FALHOU", f"variante {variant} | {label} | {det_w}")
            update_test_progress(test_id, f"ESCRITA FALHOU na variante {variant}",
                                 f"{label} em {hex(addr)}: {det_w}. A escrita NAO ocorreu.",
                                 status="FAIL_ESCRITA_NAO_OCORREU")
            print(f"!!! escrita nao ocorreu em {hex(addr)}: {det_w}")
            return False
        time.sleep(0.15)

        ping_ok = check_ping()
        telnet_ok = check_telnet_alive(s)
        if not ping_ok or not telnet_ok:
            log_sweep(addr, None, block_label, None, val, None, None, ping_ok, telnet_ok,
                      None, "CONNECTION_LOST", f"variante {variant} | {label}")
            update_test_progress(test_id, f"ABORTADO na variante {variant}",
                                 f"{label} em {hex(addr)} — ping={ping_ok} telnet={telnet_ok}",
                                 status="ABORTED_CONNECTION_LOST")
            print(f"\n!!! ABORTADO: {label} em {hex(addr)} !!!")
            return False

        log_sweep(addr, None, block_label, None, val, None, None, ping_ok, telnet_ok,
                  None, "OK", f"variante {variant} | {label} | {origem}")

    time.sleep(0.4)

    # Verificação pelo caminho válido: chip id no endereço certo
    chipid_after = [read_chipid_byte(s) for _ in range(3)]
    conntyp_after = read_conntyp_dword(s)
    print(f"  DEPOIS: B2_CHIP_ID(0x11b)={chipid_after}  dword(0x118)={conntyp_after}")

    # Rebind do sky2 — o probe reimprime o chip id que ele leu
    run_cmd(s, "dmesg -c > /dev/null 2>&1 || true", wait=0.3)
    run_cmd(s, f"echo -n '{PCI_ID}' > /sys/bus/pci/drivers/sky2/unbind 2>/dev/null; true", wait=0.4)
    run_cmd(s, f"echo -n '{PCI_ID}' > /sys/bus/pci/drivers/sky2/bind 2>/dev/null; true", wait=0.8)
    dmesg_after = run_cmd(s, "dmesg | tail -15", wait=0.6)
    iplink = run_cmd(s, "ip link show", wait=0.4)

    chipid_live = None
    m = re.search(r'unsupported chip type 0x([0-9a-fA-F]+)', dmesg_after)
    if m:
        chipid_live = m.group(1)

    print(f"  dmesg pos-rebind:\n{dmesg_after.strip()[:600]}")

    if "eth0" in iplink:
        result = "ETH0_APPEARED"
    elif chipid_after and any(v and v != "00" for v in chipid_after):
        result = "CHIPID_NONZERO"
    else:
        result = "NO_EFFECT"

    log_sweep(ADDR_CHIPID_BYTE, "B2_CHIP_ID", block_label, chipid_before,
              "hold=1 final (seq correta 3 passos)", chipid_after[0], chipid_after[-1],
              True, True, iplink.strip(), result,
              f"variante {variant} pulse={hex(pulse_addr)} | {origem} | "
              f"chipid_seq={chipid_after} conntyp={conntyp_before}->{conntyp_after} "
              f"| sky2_dmesg_chipid={chipid_live}")

    update_test_progress(test_id, f"VARIANTE {variant} concluída",
                         f"chipid {chipid_before} -> {chipid_after} | sky2 leu 0x{chipid_live} | result={result}")
    return True


def main():
    print("=" * 74)
    print("SEQUÊNCIA CORRETA (pulse=1, hold=1, pulse=0 — hold FICA em 1) nos 2 offsets")
    print("=" * 74)

    test_id = create_test_record(
        "Fase 10",
        "Sequencia correta AHCI/xHCI aplicada a GBE (2 offsets de pulse)",
        "BAR2 BPCIE glue hold=0xc8980020, pulse=0xc8980074 e 0xc8980060 + B2_CHIP_ID 0xc200011b",
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
        print(f"ERRO DE CONEXÃO: {e}")
        sys.exit(1)

    for variant, pulse_off, origem in VARIANTS:
        print(f"\n--- VARIANTE {variant}: pulse offset {hex(pulse_off)} ({origem}) ---")
        if not run_variant(s, test_id, variant, pulse_off, origem):
            print("Interrompido por perda de conexão — verifique o console fisicamente.")
            return
        time.sleep(0.5)

    iplink_final = run_cmd(s, "ip link show", wait=0.4)
    s.close()

    status_final = "OK_ETH0_ACTIVE" if "eth0" in iplink_final else "OK_SEQ_CORRETA_SEM_ETH0"
    update_test_progress(test_id, "Teste das duas variantes concluído",
                         f"ip link final:\n{iplink_final.strip()}", status=status_final)

    print("\n" + "=" * 74)
    print(f"Concluído (test_history id={test_id}, status={status_final})")
    print("Ver write_sweep_results com block_label LIKE 'CORRECT_SEQ_VAR_%'")
    print("=" * 74)


if __name__ == "__main__":
    main()
