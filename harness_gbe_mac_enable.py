#!/usr/bin/env python3
"""
harness_gbe_mac_enable.py — Testa a hipótese de que BAR0+0x34 e BAR0+0x38 são
o "enable" dos MAC cores da GBE Baikal (MTS), medindo o efeito por DIFF
COMPLETO da BAR0 contra o baseline de 1024 dwords já capturado.

FUNDAMENTO (decompilação `dc5a31f0`, rotina "up" do MAC no Orbis):
    puVar8 = BAR0 + 0x34;  uVar3 = in(puVar8) | 1;  out(puVar8, uVar3);
    puVar8 = BAR0 + 0x38;  uVar3 = in(puVar8) | 1;  out(puVar8, uVar3);
Medido ao vivo: ambos leem 0x00000000 — o passo de enable nunca rodou no Linux.

O QUE ESTE HARNESS **NÃO** FAZ, e por quê (tudo decidido por medição):

 1. NÃO habilita Bus Master (`setpci COMMAND=0x0546`).
    A mesma rotina `dc5a31f0` programa os anéis de DMA e escreve os endereços
    FÍSICOS deles em BAR0+0x40/0x44/0x48/0x50. Medido ao vivo nesses offsets:
    0x100042a0, 0x10000000, 0x10004000 — e `/proc/iomem` ao vivo mostra
    `00700000-7efe7fff : System RAM`, que CONTÉM 0x10000000. Ou seja, são
    ponteiros para RAM que o Linux usa. Com BME ligado, o MAC passaria a
    escrever pacotes recebidos nessa memória → corrupção silenciosa.
    Com BME desligado o bridge PCI bloqueia qualquer master do dispositivo:
    o MAC habilita, mas não alcança a RAM. Mesma informação, sem o risco.

 2. NÃO faz rebind do `sky2`.
    Medido: o hardware é MTS (`if_mts.c`, "Baikal GBE controller"), não um
    Marvell Yukon. O `sky2` é o driver errado; se aceitasse o chip id por
    acaso, passaria a escrever offsets de Yukon em registradores MTS.

 3. NÃO espera "chip ID do Yukon 2 (0x0a/0x0b)" como sucesso.
    Esse critério vinha de um plano escrito e é inalcançável por construção
    neste silício.

CRITÉRIO DE SUCESSO (medido, e falseável):
    diff completo dos 1024 dwords da BAR0 contra o baseline em
    `bar0_register_map`. Se o MAC sair do reset, esperam-se registradores
    novos não-zero e/ou contadores voltando a contar. Se NADA mudar, a
    interpretação de que 0x34/0x38 são o enable está ERRADA e cai — com dado.

Grava em test_history (Fase 14) e write_sweep_results
(block_label='MAC_ENABLE_34_38' e 'MAC_ENABLE_DIFF').
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

BAR0_BASE = 0xc2000000
BAR0_SIZE = 0x1000
CHUNK_DWORDS = 64

ADDR_34 = BAR0_BASE + 0x34
ADDR_38 = BAR0_BASE + 0x38

DWORD_RE = re.compile(r'\b([0-9a-fA-F]{8})\b')


# ---------------- SQLite ----------------

def create_test_record(phase, test_name, target, initial_action):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO test_history (timestamp, phase, test_name, target_component, action_taken, status, complementary_info)
    VALUES (?, ?, ?, ?, ?, 'PENDING', 'Inicializando teste de enable do MAC...');
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


def log_sweep(address, reg_name, block_label, before, written, after, ping_ok, telnet_ok, result, notes):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO write_sweep_results
        (address, reg_name, block_label, value_before, value_written, value_after_immediate,
         value_after_settle, ping_ok, telnet_ok, ip_link_snapshot, result, timestamp, notes)
    VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, NULL, ?, ?, ?);
    """, (hex(address) if isinstance(address, int) else address, reg_name, block_label,
          before, written, after, int(ping_ok), int(telnet_ok), result, ts, notes))
    conn.commit()
    conn.close()


def load_baseline():
    """Baseline dos 1024 dwords capturado na Fase 13."""
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    base = {}
    for addr, s1, s2, s3, cls in cur.execute(
            "SELECT address, sample1, sample2, sample3, classification FROM bar0_register_map;"):
        off = int(addr, 16) - BAR0_BASE
        base[off] = {"samples": [s1, s2, s3], "classification": cls}
    conn.close()
    return base


# ---------------- Telnet ----------------

def read_until_prompt(s, prompt=b"~ # ", timeout=10):
    data = b""
    end = time.time() + timeout
    while time.time() < end:
        try:
            s.settimeout(0.5)
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
            if prompt in data:
                break
        except socket.timeout:
            pass
    return data


def run_cmd(s, cmd, wait=0.3, timeout=10):
    s.sendall(cmd.encode('ascii') + b"\n")
    time.sleep(wait)
    return read_until_prompt(s, timeout=timeout).decode('ascii', errors='replace')


def read_dword(s, addr):
    raw = run_cmd(s, f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4", wait=0.2)
    m = DWORD_RE.search(raw)
    return m.group(1) if m else None


def scan_bar0(s):
    """Varre os 1024 dwords. Retorna {offset: valor_hex_ou_None}."""
    out = {}
    off = 0
    while off < BAR0_SIZE:
        n = min(CHUNK_DWORDS, (BAR0_SIZE - off) // 4)
        addr = BAR0_BASE + off
        cmd = (f"dd if=/dev/mem bs=4 count={n} skip=$(( {hex(addr)} / 4 )) "
               f"2>/dev/null | od -An -tx4 -v")
        raw = run_cmd(s, cmd, wait=0.45, timeout=12)
        lines = [l for l in raw.splitlines() if 'dd if=' not in l and '~ #' not in l and 'od -An' not in l]
        vals = []
        for line in lines:
            vals.extend(DWORD_RE.findall(line))
        vals = vals[:n]
        vals += [None] * (n - len(vals))
        for i in range(n):
            out[off + i * 4] = vals[i]
        off += n * 4
    return out


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


# ---------------- Principal ----------------

def main():
    print("=" * 78)
    print("ENABLE DO MAC (BAR0+0x34 |= 1, BAR0+0x38 |= 1) — efeito medido por diff da BAR0")
    print("SEM Bus Master | SEM rebind do sky2 — ambos descartados por medição")
    print("=" * 78)

    baseline = load_baseline()
    if len(baseline) < 1024:
        print(f"AVISO: baseline tem {len(baseline)}/1024 dwords. Rode antes o harness_gbe_bar0_full_map.py.")
        if len(baseline) == 0:
            sys.exit(1)
    print(f"Baseline carregado: {len(baseline)} dwords da Fase 13.\n")

    test_id = create_test_record(
        "Fase 14",
        "Enable do MAC GBE via BAR0+0x34/0x38 (|=1), efeito medido por diff completo da BAR0",
        f"GBE BAR0 {hex(ADDR_34)} e {hex(ADDR_38)} | diff de 1024 dwords",
        "Conectando ao Telnet"
    )

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(10)
        s.connect((PS4_IP, PS4_PORT))
        read_until_prompt(s, timeout=4)
        update_test_progress(test_id, "Conexão Telnet", "Conectado na porta 23.")
    except Exception as e:
        update_test_progress(test_id, "Conexão Telnet", f"ERRO: {e}", status="FAIL_CONNECTION")
        print(f"ERRO DE CONEXÃO: {e}")
        sys.exit(1)

    # --- Confirma que BME continua desligado (não vamos ligá-lo) ---
    cmd_cfg = run_cmd(s, "dd if=/sys/bus/pci/devices/0000:00:14.1/config bs=1 count=8 2>/dev/null | od -An -tx1 -v", wait=0.4)
    print(f"PCI config[0..7]: {' '.join(cmd_cfg.split())[:60]}")
    update_test_progress(test_id, "Estado do PCI COMMAND", "BME deve permanecer desligado (0x0542)")

    # --- Varredura ANTES ---
    print("\n--- varredura ANTES do enable ---")
    before_map = scan_bar0(s)
    nz_before = sum(1 for v in before_map.values() if v and v != "00000000")
    print(f"  não-zero antes: {nz_before}")

    v34_before = before_map.get(0x34)
    v38_before = before_map.get(0x38)
    print(f"  0x34 = {v34_before}   0x38 = {v38_before}")

    # --- As DUAS únicas escritas (via printf octal + dd; devmem NAO existe) ---
    resultados_escrita = {}

    for idx, (addr, vbefore, nome) in enumerate(
            [(ADDR_34, v34_before, "MTS_MAC_CORE1_ENABLE"),
             (ADDR_38, v38_before, "MTS_MAC_CORE2_ENABLE")], start=1):

        novo = (int(vbefore or "0", 16) | 1) & 0xffffffff
        update_test_progress(test_id, f"ESCRITA {idx}/2", f"{hex(addr)}: {vbefore} |= 1 -> {novo:08x}")

        cmd = build_write_cmd(addr, novo)
        saida = run_cmd(s, cmd, wait=0.4)
        escrita_ok, detalhe = parse_write_result(saida)
        print(f"  escrita em {hex(addr)}: {'CONFIRMADA' if escrita_ok else 'FALHOU'} ({detalhe})")

        if not escrita_ok:
            # NUNCA reportar como "sem efeito": a escrita nao ocorreu
            log_sweep(addr, nome, "MAC_ENABLE_34_38", vbefore, f"{novo:08x}", None,
                      True, True, "ESCRITA_FALHOU", f"{detalhe} | saida: {saida.strip()[:200]}")
            update_test_progress(test_id, f"ESCRITA {idx}/2 FALHOU",
                                 f"{hex(addr)}: {detalhe}. Nao e 'sem efeito' — a escrita nao ocorreu.",
                                 status="FAIL_ESCRITA_NAO_OCORREU")
            print(f"\n!!! A ESCRITA NAO OCORREU em {hex(addr)} — abortando !!!")
            return

        time.sleep(0.25)
        ping_ok, telnet_ok = check_ping(), check_telnet_alive(s)
        vafter = read_dword(s, addr)
        resultados_escrita[addr] = vafter

        log_sweep(addr, nome, "MAC_ENABLE_34_38", vbefore, f"{novo:08x}", vafter,
                  ping_ok, telnet_ok,
                  "OK" if (ping_ok and telnet_ok) else "CONNECTION_LOST",
                  f"dc5a31f0: BAR0+{hex(addr - BAR0_BASE)} |= 1 (rotina up do MAC) | escrita: {detalhe}")
        print(f"  {hex(addr)}: {vbefore} -> {vafter}   ping={ping_ok} telnet={telnet_ok}")

        if not (ping_ok and telnet_ok):
            update_test_progress(test_id, f"ABORTADO após escrita em {hex(addr)}",
                                 f"ping={ping_ok} telnet={telnet_ok}", status="ABORTED_CONNECTION_LOST")
            print(f"\n!!! ABORTADO após {hex(addr)} !!!")
            return

    v34_after = resultados_escrita.get(ADDR_34)
    v38_after = resultados_escrita.get(ADDR_38)

    # --- Varredura DEPOIS ---
    print("\n--- varredura DEPOIS do enable ---")
    time.sleep(1.0)
    after_map = scan_bar0(s)
    nz_after = sum(1 for v in after_map.values() if v and v != "00000000")
    print(f"  não-zero depois: {nz_after}")

    # --- DIFF ---
    mudou = []
    novos_nz = []
    for off in sorted(after_map):
        a = after_map[off]
        b = before_map.get(off)
        if a != b:
            mudou.append((off, b, a))
            if b == "00000000" and a and a != "00000000":
                novos_nz.append((off, a))

    # registradores marcados VOLATILE no baseline mudam sozinhos: separar
    volateis = {o for o, d in baseline.items() if d["classification"] == "VOLATILE"}
    mudou_sem_volateis = [(o, b, a) for (o, b, a) in mudou if o not in volateis]

    print(f"\n  dwords que mudaram: {len(mudou)}  (excluindo voláteis conhecidos: {len(mudou_sem_volateis)})")
    print(f"  novos não-zero: {len(novos_nz)}")

    if mudou_sem_volateis:
        print("\n  MUDANÇAS (fora dos voláteis já conhecidos):")
        for off, b, a in mudou_sem_volateis[:40]:
            print(f"    +0x{off:03X}: {b} -> {a}")

    iplink = run_cmd(s, "ip link show", wait=0.4)
    dmesg = run_cmd(s, "dmesg | tail -8", wait=0.5)
    s.close()

    # --- Veredito ---
    if "eth0" in iplink:
        result = "ETH0_APPEARED"
        veredito = "eth0 APARECEU"
    elif novos_nz:
        result = "MAC_RESPONDEU"
        veredito = (f"MAC REAGIU: {len(novos_nz)} registradores passaram de zero para não-zero. "
                    f"A hipótese de 0x34/0x38 = enable do MAC core está SUSTENTADA.")
    elif mudou_sem_volateis:
        result = "MUDANCA_PARCIAL"
        veredito = (f"{len(mudou_sem_volateis)} registradores mudaram (fora dos voláteis). "
                    f"Efeito real, mas sem novos não-zero — analisar o diff.")
    else:
        result = "SEM_EFEITO_HIPOTESE_CAI"
        veredito = ("NADA mudou além dos voláteis já conhecidos. A interpretação de que "
                    "0x34/0x38 são o enable do MAC core NÃO se sustenta — descartar com dado.")

    log_sweep("diff", "BAR0_FULL_DIFF", "MAC_ENABLE_DIFF",
              str(nz_before), "0x34|=1 ; 0x38|=1", str(nz_after), True, True, result,
              f"mudaram={len(mudou)} (sem volateis={len(mudou_sem_volateis)}) novos_nz={len(novos_nz)} "
              f"| detalhe: {mudou_sem_volateis[:20]}")

    resumo = (f"não-zero {nz_before} -> {nz_after} | mudaram {len(mudou)} "
              f"(sem voláteis {len(mudou_sem_volateis)}) | novos não-zero {len(novos_nz)}\n"
              f"0x34: {v34_before}->{v34_after}  0x38: {v38_before}->{v38_after}\n{veredito}")
    update_test_progress(test_id, "Teste de enable do MAC concluído", resumo, status=result)

    print("\n" + "=" * 78)
    print(veredito)
    print("=" * 78)
    print(f"\nip link:\n{iplink.strip()[:400]}")
    print(f"\ndmesg:\n{dmesg.strip()[:400]}")


if __name__ == "__main__":
    main()
