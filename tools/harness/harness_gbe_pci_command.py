#!/usr/bin/env python3
"""
harness_gbe_pci_command.py — Compara o PCI config space (primeiros 64 bytes,
faixa comprovadamente segura) da GBE com o dos periféricos que FUNCIONAM
(AHCI e xHCI), focando no registrador COMMAND (offset 0x04).

100% LEITURA — não escreve nada.

MOTIVO (hipótese levantada 2026-07-22): confirmamos que a BAR0 da GBE devolve
zeros REAIS (não é barramento flutuante). Mas existe uma explicação
alternativa que nunca checamos: se o bit **Memory Space Enable** (bit 1 do
registrador COMMAND) estiver LIMPO na função 00:14.1, o dispositivo não
decodifica a faixa MMIO da BAR0 — e aí os zeros que lemos não vêm do MAC, e
sim de um ciclo não reclamado no barramento. Isso invalidaria toda leitura de
BAR0 da GBE feita até hoje.

Isso é plausível porque o probe do sky2 FALHOU (`error -95`): o
`pci_enable_device()` liga o MSE no início do probe, mas o caminho de erro
normalmente chama `pci_disable_device()`, que o desliga de novo. Ou seja, a
GBE pode estar agora sem decodificar MMIO nenhuma.

Comparação (mesmo southbridge Baikal, funções irmãs):
    00:14.1 = 0x90d8 GBE   (quebrada)
    00:14.2 = 0x90d9 AHCI  (funciona — discos sda/sdb ativos)
    00:14.7 = 0x90de xHCI  (funciona — dispositivos USB ativos)

Segurança: lê apenas 64 bytes com `dd bs=1 count=64` (limite explícito),
nunca o espaço estendido (>0x40), que é HIGH_RISK_BUS_LOCKUP no SQLite
(id=7) e derruba o console.

Registra em test_history (Fase 12) e write_sweep_results
(block_label='PCI_COMMAND_COMPARE').
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

DEVICES = [
    ("0000:00:14.1", "GBE  (0x90d8)", "QUEBRADA"),
    ("0000:00:14.2", "AHCI (0x90d9)", "funciona"),
    ("0000:00:14.7", "xHCI (0x90de)", "funciona"),
    ("0000:00:14.4", "PCIE (0x90db)", "glue/bpcie"),
]

COMMAND_BITS = [
    (0, "I/O Space Enable"),
    (1, "Memory Space Enable"),
    (2, "Bus Master Enable"),
    (6, "Parity Error Response"),
    (8, "SERR# Enable"),
    (10, "Interrupt Disable"),
]

BYTE_RE = re.compile(r'\b([0-9a-fA-F]{2})\b')


def create_test_record(phase, test_name, target, initial_action):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO test_history (timestamp, phase, test_name, target_component, action_taken, status, complementary_info)
    VALUES (?, ?, ?, ?, ?, 'PENDING', 'Inicializando comparativo de PCI COMMAND...');
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


def log_device(pci_id, label, command_val, bar0, notes, result):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO write_sweep_results
        (address, reg_name, block_label, value_before, value_written, value_after_immediate,
         value_after_settle, ping_ok, telnet_ok, ip_link_snapshot, result, timestamp, notes)
    VALUES (?, ?, 'PCI_COMMAND_COMPARE', ?, NULL, ?, NULL, 1, 1, NULL, ?, ?, ?);
    """, (pci_id, f"{label} COMMAND", command_val, bar0, result, ts, notes))
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


def run_cmd(s, cmd, wait=0.3):
    s.sendall(cmd.encode('ascii') + b"\n")
    time.sleep(wait)
    return read_until_prompt(s).decode('ascii', errors='replace')


def read_config64(s, pci_id):
    """Lê APENAS os primeiros 64 bytes do config space (limite explícito no dd)."""
    cmd = (f"dd if=/sys/bus/pci/devices/{pci_id}/config bs=1 count=64 2>/dev/null "
           f"| od -An -tx1 -v")
    raw = run_cmd(s, cmd, wait=0.5)
    lines = [l for l in raw.splitlines() if 'dd if=' not in l and '~ #' not in l]
    all_bytes = []
    for line in lines:
        all_bytes.extend(BYTE_RE.findall(line))
    return all_bytes[:64]


def decode_command(cfg_bytes):
    if len(cfg_bytes) < 6:
        return None, None
    # little-endian: byte 0x04 = low, byte 0x05 = high
    cmd = int(cfg_bytes[5], 16) << 8 | int(cfg_bytes[4], 16)
    return cmd, f"{cmd:04x}"


def main():
    print("=" * 78)
    print("COMPARATIVO PCI COMMAND — GBE vs periféricos que funcionam (só leitura, 64B)")
    print("=" * 78)

    test_id = create_test_record(
        "Fase 12",
        "Comparativo PCI COMMAND (Memory Space Enable) GBE vs AHCI/xHCI",
        "PCI config 0x00-0x3f de 00:14.1 (GBE), 00:14.2 (AHCI), 00:14.7 (xHCI), 00:14.4 (glue)",
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

    results = {}

    for pci_id, label, estado in DEVICES:
        cfg = read_config64(s, pci_id)
        if len(cfg) < 16:
            print(f"{label}: falha ao ler config ({len(cfg)} bytes)")
            log_device(pci_id, label, None, None, f"{estado} | leitura incompleta", "READ_FAIL")
            continue

        cmd_val, cmd_hex = decode_command(cfg)
        if cmd_val is None:
            print(f"{label}: nao foi possivel decodificar o COMMAND")
            log_device(pci_id, label, None, None, f"{estado} | COMMAND indecifravel", "READ_FAIL")
            continue
        bar0 = "".join(reversed(cfg[0x10:0x14]))
        vendor = "".join(reversed(cfg[0x00:0x02]))
        device = "".join(reversed(cfg[0x02:0x04]))
        status_reg = "".join(reversed(cfg[0x06:0x08]))

        results[label] = (cmd_val, cmd_hex, bar0)

        bits_on = [name for bit, name in COMMAND_BITS if cmd_val & (1 << bit)]
        print(f"\n--- {label}  [{estado}]  {pci_id} ---")
        print(f"  vendor:device = {vendor}:{device}   status={status_reg}")
        print(f"  COMMAND = 0x{cmd_hex}   BAR0 = 0x{bar0}")
        print(f"  bits ativos: {', '.join(bits_on) if bits_on else '(nenhum)'}")

        mse = bool(cmd_val & 0x02)
        result = "MSE_ON" if mse else "MSE_OFF"
        log_device(pci_id, label, f"0x{cmd_hex}", f"0x{bar0}",
                   f"{estado} | bits: {'; '.join(bits_on)} | status={status_reg} | vendor:device={vendor}:{device}",
                   result)

    s.close()

    print("\n" + "=" * 78)
    print("ANÁLISE")
    print("=" * 78)

    gbe = results.get("GBE  (0x90d8)")
    ahci = results.get("AHCI (0x90d9)")
    xhci = results.get("xHCI (0x90de)")

    if gbe and gbe[0] is not None:
        gbe_mse = bool(gbe[0] & 0x02)
        print(f"GBE  COMMAND=0x{gbe[1]}  Memory Space Enable = {'LIGADO' if gbe_mse else 'DESLIGADO'}")
        if ahci and ahci[0] is not None:
            print(f"AHCI COMMAND=0x{ahci[1]}  MSE = {'LIGADO' if ahci[0] & 0x02 else 'DESLIGADO'}")
        if xhci and xhci[0] is not None:
            print(f"xHCI COMMAND=0x{xhci[1]}  MSE = {'LIGADO' if xhci[0] & 0x02 else 'DESLIGADO'}")
        print()
        if not gbe_mse:
            conclusao = ("ACHADO CRÍTICO: a GBE está com Memory Space Enable DESLIGADO. "
                         "Ela não decodifica a faixa da BAR0 — TODA leitura de 0xc2000xxx feita "
                         "até hoje leu ciclo nao reclamado, nao o MAC. Precisa religar o MSE "
                         "(setpci COMMAND=...) antes de qualquer conclusao sobre o MAC estar morto.")
            status = "GBE_MSE_OFF_LEITURAS_INVALIDAS"
        else:
            conclusao = ("GBE está com Memory Space Enable LIGADO — ela decodifica a BAR0 de "
                         "verdade. Confirma que os zeros vem do MAC core sem clock, e nao de "
                         "ciclo nao reclamado. Hipotese do MSE descartada.")
            status = "GBE_MSE_ON_ZEROS_REAIS"
        print(conclusao)
        update_test_progress(test_id, "Comparativo concluído", conclusao, status=status)
    else:
        update_test_progress(test_id, "Comparativo falhou", "Nao foi possivel ler o config da GBE",
                             status="FAIL_READ")

    print("=" * 78)


if __name__ == "__main__":
    main()
