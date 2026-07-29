#!/usr/bin/env python3
"""
harness_gbe_bar0_full_map.py — Mapeamento COMPLETO (100%) da BAR0 da GBE
Baikal: todos os 1024 dwords de 0x000 a 0xFFC, com N amostras por endereço
para classificar cada registrador como estável ou volátil.

100% LEITURA — não escreve nada no hardware.

CONTEXTO: até 2026-07-22 só 384 dos 1024 dwords estavam no SQLite
(0x000-0x5FC, das varreduras da Fase 6), e em amostra única. Faltavam 640
dwords (0x600-0xFFC) — justamente a metade alta, onde em controladores de
rede costumam ficar os blocos de DMA/descritores. Este harness fecha os 100%.

POR QUE MULTI-AMOSTRA: a BAR0 tem registradores voláteis já observados
(0xc200003c foi 0x10000090 e depois 0x10000f70; 0xc2000118 foi 0x00 e depois
0x0c). Para montar register map de driver, distinguir contador/status
(volátil) de config/ID/capability (estável) é essencial — e amostra única
não permite isso.

LIMITE RÍGIDO: lê apenas 0x000-0xFFF. A BAR0 tem exatamente 4 KB
(dmesg: `BAR 0 [mem 0xc2000000-0xc2000fff 64bit]`). Ler além disso sai da
faixa decodificada pelo dispositivo — foi exatamente o erro do sky2, que
fazia ioremap de 0x4000 e gerava o `resource sanity check`.

SEGURANÇA: lê em blocos de 256 bytes com verificação de ping + telnet entre
blocos, abortando na hora e registrando onde parou.

Grava em:
  - bar0_register_map  (tabela nova: amostras + classificação por endereço)
  - hardware_registers (todos os 1024, para cobertura de 100% no catálogo)
  - test_history       (Fase 13)
"""

import socket
import subprocess
import time
import re
import sqlite3
import datetime
import sys

PS4_IP = "192.168.6.128"
PS4_PORT = 23
DB_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db"

BAR0_BASE = 0xc2000000
BAR0_SIZE = 0x1000          # 4 KB — limite rígido, confirmado no dmesg
CHUNK_DWORDS = 64           # 256 bytes por leitura
N_PASSES = 3                # amostras por endereço

DWORD_RE = re.compile(r'\b([0-9a-fA-F]{8})\b')


# ---------------- SQLite ----------------

def create_test_record(phase, test_name, target, initial_action):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO test_history (timestamp, phase, test_name, target_component, action_taken, status, complementary_info)
    VALUES (?, ?, ?, ?, ?, 'PENDING', 'Inicializando mapeamento completo da BAR0...');
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


def save_map(samples_by_off):
    """samples_by_off: {offset:int -> [s1, s2, s3]}"""
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    stats = {"STABLE_ZERO": 0, "STABLE_NONZERO": 0, "VOLATILE": 0, "READ_FAIL": 0}

    for off, samples in sorted(samples_by_off.items()):
        addr = BAR0_BASE + off
        vals = [v for v in samples if v is not None]
        distinct = len(set(vals))

        if not vals:
            classification = "READ_FAIL"
        elif distinct > 1:
            classification = "VOLATILE"
        elif vals[0] == "00000000":
            classification = "STABLE_ZERO"
        else:
            classification = "STABLE_NONZERO"
        stats[classification] += 1

        s = (samples + [None, None, None])[:3]

        cur.execute("SELECT id, first_seen FROM bar0_register_map WHERE address = ?;", (hex(addr),))
        row = cur.fetchone()
        if row:
            cur.execute("""UPDATE bar0_register_map
                           SET sample1=?, sample2=?, sample3=?, distinct_values=?,
                               classification=?, last_seen=? WHERE id=?;""",
                        (s[0], s[1], s[2], distinct, classification, ts, row[0]))
        else:
            cur.execute("""INSERT INTO bar0_register_map
                (address, reg_offset, sample1, sample2, sample3, distinct_values,
                 classification, notes, first_seen, last_seen)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);""",
                        (hex(addr), hex(off), s[0], s[1], s[2], distinct, classification,
                         "GBE Baikal (MTS) BAR0 - mapeamento completo 2026-07-22", ts, ts))

        # espelha no catálogo principal para cobertura de 100%
        name = f"BAR0_MTS_{off:03X}"
        desc = (f"GBE Baikal (MTS) BAR0 offset {hex(off)} | {classification} | "
                f"amostras: {', '.join(v or 'FAIL' for v in samples)}")
        cur.execute("SELECT id FROM hardware_registers WHERE base_bar=? AND reg_offset=?;",
                    ("BAR0 (0xc2000000)", hex(addr)))
        ex = cur.fetchone()
        if ex:
            cur.execute("UPDATE hardware_registers SET reg_name=?, description=?, safe_to_read=1 WHERE id=?;",
                        (name, desc, ex[0]))
        else:
            cur.execute("""INSERT INTO hardware_registers
                (device, base_bar, reg_offset, reg_name, description, safe_to_read, safe_to_write, risk_level)
                VALUES ('Baikal GbE (MTS)', ?, ?, ?, ?, 1, 0, 'SAFE');""",
                        ("BAR0 (0xc2000000)", hex(addr), name, desc))

    conn.commit()
    conn.close()
    return stats


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


def read_chunk(s, off, n_dwords):
    """Lê n_dwords a partir de BAR0_BASE+off. Retorna lista de strings hex."""
    addr = BAR0_BASE + off
    cmd = (f"dd if=/dev/mem bs=4 count={n_dwords} skip=$(( {hex(addr)} / 4 )) "
           f"2>/dev/null | od -An -tx4 -v")
    raw = run_cmd(s, cmd, wait=0.45, timeout=12)
    lines = [l for l in raw.splitlines() if 'dd if=' not in l and '~ #' not in l and 'od -An' not in l]
    vals = []
    for line in lines:
        vals.extend(DWORD_RE.findall(line))
    return vals[:n_dwords]


def check_ping():
    try:
        return subprocess.run(["ping", "-c", "1", "-W", "2", PS4_IP],
                              capture_output=True, timeout=5).returncode == 0
    except Exception:
        return False


def main():
    total_dwords = BAR0_SIZE // 4
    print("=" * 78)
    print(f"MAPEAMENTO COMPLETO DA BAR0 DA GBE — {total_dwords} dwords (0x000..0x{BAR0_SIZE-4:03X})")
    print(f"{N_PASSES} passadas para classificar estável vs volátil — 100% LEITURA")
    print("=" * 78)

    test_id = create_test_record(
        "Fase 13",
        f"Mapeamento completo BAR0 GBE Baikal (MTS) - {total_dwords} dwords x {N_PASSES} amostras",
        f"GBE BAR0 {hex(BAR0_BASE)}..{hex(BAR0_BASE + BAR0_SIZE - 4)} (4 KB, limite do BAR)",
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

    samples_by_off = {off: [] for off in range(0, BAR0_SIZE, 4)}

    for p in range(1, N_PASSES + 1):
        print(f"\n--- passada {p}/{N_PASSES} ---")
        off = 0
        while off < BAR0_SIZE:
            n = min(CHUNK_DWORDS, (BAR0_SIZE - off) // 4)
            vals = read_chunk(s, off, n)

            if len(vals) != n:
                update_test_progress(
                    test_id, f"Leitura incompleta em {hex(BAR0_BASE + off)}",
                    f"esperado {n} dwords, obtido {len(vals)} — passada {p}")
                # preenche o que veio, marca o resto como falha
                vals = vals + [None] * (n - len(vals))

            for i in range(n):
                samples_by_off[off + i * 4].append(vals[i])

            nz = sum(1 for v in vals if v and v != "00000000")
            print(f"  0x{off:03X}..0x{off + n*4 - 4:03X}  ok={sum(1 for v in vals if v):3d}/{n}  nao-zero={nz}")

            if not check_ping():
                update_test_progress(
                    test_id, "ABORTADO — perda de ping",
                    f"parou em {hex(BAR0_BASE + off)} na passada {p}",
                    status="ABORTED_PING_LOST")
                print(f"\n!!! ABORTADO em {hex(BAR0_BASE + off)} — sem ping !!!")
                s.close()
                save_map(samples_by_off)
                return

            off += n * 4

        update_test_progress(test_id, f"Passada {p}/{N_PASSES} concluída",
                             f"{total_dwords} dwords lidos")
        time.sleep(0.5)

    s.close()

    stats = save_map(samples_by_off)

    lidos = sum(1 for v in samples_by_off.values() if any(x is not None for x in v))
    cobertura = 100.0 * lidos / total_dwords

    resumo = (f"COBERTURA: {lidos}/{total_dwords} dwords ({cobertura:.1f}%) | "
              f"estáveis não-zero: {stats['STABLE_NONZERO']} | "
              f"estáveis zero: {stats['STABLE_ZERO']} | "
              f"VOLÁTEIS: {stats['VOLATILE']} | falhas: {stats['READ_FAIL']}")

    print("\n" + "=" * 78)
    print(resumo)
    print("=" * 78)

    status = "OK_BAR0_100PCT" if cobertura >= 99.9 else "PARCIAL"
    update_test_progress(test_id, "Mapeamento completo da BAR0 concluído", resumo, status=status)

    # destaque: registradores voláteis e não-zero são os interessantes p/ o driver
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    print("\nVOLÁTEIS (candidatos a contador/status):")
    for a, o, s1, s2, s3 in cur.execute(
            "SELECT address, reg_offset, sample1, sample2, sample3 FROM bar0_register_map "
            "WHERE classification='VOLATILE' ORDER BY address;"):
        print(f"  {a} (+{o}): {s1} -> {s2} -> {s3}")
    n_nz = cur.execute("SELECT COUNT(*) FROM bar0_register_map WHERE classification='STABLE_NONZERO';").fetchone()[0]
    print(f"\nESTÁVEIS NÃO-ZERO: {n_nz} (candidatos a config/ID/capability)")
    conn.close()


if __name__ == "__main__":
    main()
