#!/usr/bin/env python3
"""
harnes_gbe_reandoly.py — Reteste Read-Only de TODOS os endereços já mapeados no SQLite.

Diferença em relação ao harness_gbe.py (varredura original, que também FAZ PUSH no
hardware — devmem, echo em /proc/ps4_icc, unbind/bind de driver):
  - Este script NÃO escreve em NADA. Só leitura (dd if=/dev/mem | od).
  - Não gera endereços novos: lê a lista de endereços já cadastrados em
    hardware_registers e re-testa cada um.
  - Usa o ENDEREÇO DE MEMÓRIA (absoluto, ex. 0xc890a030) como chave de
    busca/gravação na tabela readonly_verification (UNIQUE), não o par
    (base_bar, reg_offset) nem o reg_name.
  - Objetivo: comparar a leitura de hoje com a leitura anterior (armazenada na
    própria readonly_verification) e com o valor-baseline gravado na
    description de hardware_registers, para detectar FALSOS POSITIVOS —
    registros marcados safe_to_read=1 que hoje não respondem mais, ou que
    mudam de valor de forma incompatível com um registrador estático.

Não altera hardware_registers (não mexe em safe_to_read/safe_to_write/risk_level
da tabela original) — todo o resultado do reteste fica isolado em
readonly_verification, para não estragar o mapeamento já validado.
"""

import socket
import time
import sys
import re
import sqlite3
import datetime
import subprocess

PS4_IP = "192.168.6.128"
PS4_PORT = 23

DB_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db"

BASE_RE = re.compile(r"0x[0-9a-fA-F]+")
OFFSET_RE = re.compile(r"^0x[0-9a-fA-F]+$")
VALUE_RE = re.compile(r"\b([0-9a-fA-F]{8})\b")


def get_db_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
    CREATE TABLE IF NOT EXISTS readonly_verification (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        address TEXT NOT NULL UNIQUE,
        reg_name TEXT NOT NULL,
        base_bar TEXT NOT NULL,
        reg_offset TEXT NOT NULL,
        baseline_value TEXT,
        previous_value TEXT,
        current_value TEXT,
        read_ok INTEGER NOT NULL,
        changed_since_last INTEGER NOT NULL DEFAULT 0,
        changed_since_baseline INTEGER NOT NULL DEFAULT 0,
        suspected_false_positive INTEGER NOT NULL DEFAULT 0,
        safe_to_read_db INTEGER,
        test_count INTEGER NOT NULL DEFAULT 0,
        last_tested TEXT,
        notes TEXT
    );
    """)
    conn.commit()
    return conn


def resolve_address(base_bar, reg_offset):
    """Resolve o endereço absoluto de 32 bits a partir de base_bar + reg_offset.

    Convenção usada pelo harness_gbe.py ao gravar (e confirmada nos dados reais
    do banco): reg_offset é relativo à base extraída de base_bar, ex.
    base_bar='BAR2 (0xc8800000)', reg_offset='0x10a030' -> 0xc890a030.
    Entradas com faixas ('0x40..0xFF'), texto livre ('kern.printf') ou sem base
    numérica ('Kernel Text', 'MMIO') não são resolvíveis e são puladas.
    """
    base_match = BASE_RE.search(base_bar)
    if not base_match:
        return None
    if not OFFSET_RE.match(reg_offset.strip()):
        return None
    base = int(base_match.group(0), 16)
    offset = int(reg_offset.strip(), 16)
    return base + offset


def extract_baseline_value(description):
    m = re.search(r"Valor lido ao vivo:\s*0x([0-9a-fA-F]{8})", description or "")
    return m.group(1).lower() if m else None


def load_targets():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
        SELECT reg_name, base_bar, reg_offset, description, safe_to_read
        FROM hardware_registers
        ORDER BY id;
    """)
    rows = cur.fetchall()
    conn.close()

    resolved, skipped = [], []
    seen_addrs = set()
    for reg_name, base_bar, reg_offset, description, safe_to_read in rows:
        addr = resolve_address(base_bar, reg_offset)
        if addr is None:
            skipped.append((reg_name, base_bar, reg_offset))
            continue
        if addr in seen_addrs:
            # já temos esse endereço absoluto cadastrado por outra linha (reg_name
            # duplicado/alias) — mantém só a primeira ocorrência como alvo de teste
            continue
        seen_addrs.add(addr)
        resolved.append({
            "reg_name": reg_name,
            "base_bar": base_bar,
            "reg_offset": reg_offset,
            "address": addr,
            "baseline_value": extract_baseline_value(description),
            "safe_to_read": safe_to_read,
        })
    return resolved, skipped


def create_test_record(phase, test_name, target, initial_action):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO test_history (timestamp, phase, test_name, target_component, action_taken, status, complementary_info)
    VALUES (?, ?, ?, ?, ?, 'PENDING', 'Inicializando reteste read-only...');
    """, (ts, phase, test_name, target, initial_action))
    test_id = cur.lastrowid
    conn.commit()
    conn.close()
    return test_id


def update_test_progress(test_id, action, info, status="PENDING"):
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    UPDATE test_history
    SET action_taken = ?, complementary_info = ?, status = ?
    WHERE id = ?;
    """, (action, info, status, test_id))
    conn.commit()
    conn.close()
    print(f"[{status}] {action} -> {info[:80]}...")


def upsert_verification(conn, target, current_value, read_ok):
    cur = conn.cursor()
    addr_hex = hex(target["address"])
    cur.execute("SELECT current_value, test_count FROM readonly_verification WHERE address = ?;", (addr_hex,))
    row = cur.fetchone()
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    baseline = target["baseline_value"]
    changed_since_baseline = int(bool(baseline and current_value and baseline.lower() != current_value.lower()))

    if row is None:
        last_current, test_count = None, 0
    else:
        last_current, test_count = row

    changed_since_last = int(bool(last_current and current_value and last_current.lower() != current_value.lower()))

    # Falso positivo suspeito: estava marcado safe_to_read=1 no mapeamento
    # original (ou já leu valor antes) mas hoje não conseguimos mais ler.
    suspected_fp = int(bool((target["safe_to_read"] == 1 or last_current) and not read_ok))

    if row is None:
        cur.execute("""
        INSERT INTO readonly_verification
            (address, reg_name, base_bar, reg_offset, baseline_value, previous_value,
             current_value, read_ok, changed_since_last, changed_since_baseline,
             suspected_false_positive, safe_to_read_db, test_count, last_tested, notes)
        VALUES (?, ?, ?, ?, ?, NULL, ?, ?, 0, ?, ?, ?, 1, ?, ?);
        """, (addr_hex, target["reg_name"], target["base_bar"], target["reg_offset"],
              baseline, current_value, int(read_ok), changed_since_baseline, suspected_fp,
              target["safe_to_read"], ts, "" if read_ok else "FALHA na primeira releitura"))
    else:
        cur.execute("""
        UPDATE readonly_verification
        SET reg_name = ?, base_bar = ?, reg_offset = ?, baseline_value = COALESCE(baseline_value, ?),
            previous_value = ?, current_value = ?, read_ok = ?,
            changed_since_last = ?, changed_since_baseline = ?,
            suspected_false_positive = ?, safe_to_read_db = ?,
            test_count = ?, last_tested = ?
        WHERE address = ?;
        """, (target["reg_name"], target["base_bar"], target["reg_offset"], baseline,
              last_current, current_value, int(read_ok),
              changed_since_last, changed_since_baseline,
              suspected_fp, target["safe_to_read"], test_count + 1, ts, addr_hex))
    conn.commit()
    return changed_since_last, changed_since_baseline, suspected_fp


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


def run_cmd(s, cmd, wait=0.12):
    s.sendall(cmd.encode('ascii') + b"\n")
    time.sleep(wait)
    return read_until_prompt(s).decode('ascii', errors='replace')


def run_capture_dmesg():
    try:
        res = subprocess.run(["python3", "capture_dmesg.py", PS4_IP, str(PS4_PORT)], capture_output=True, text=True, timeout=15)
        print(f"[CAPTURE DMESG] {res.stdout.strip()}")
        return res.stdout
    except Exception as e:
        print(f"[CAPTURE DMESG ERRO] {e}")
        return str(e)


def main():
    print("=" * 60)
    print("HARNESS GBE — RETESTE READ-ONLY DE TODOS OS ENDEREÇOS MAPEADOS (SEM PUSH)")
    print("=" * 60)

    targets, skipped = load_targets()
    print(f"Endereços resolvidos para reteste: {len(targets)}")
    print(f"Linhas puladas (sem endereço absoluto resolvível): {len(skipped)}")

    test_id = create_test_record(
        "Fase 7", "Reteste Read-Only Completo (detecção de falso positivo)",
        "Todos os registradores em hardware_registers", "Conectando ao Telnet (somente leitura)"
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

    conn = get_db_connection()

    changed_last_list = []
    changed_baseline_list = []
    false_positive_list = []
    ok_count = 0
    fail_count = 0

    for i, target in enumerate(targets):
        addr = target["address"]
        cmd = f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(addr)} / 4 )) 2>/dev/null | od -An -tx4"
        raw = run_cmd(s, cmd).strip()
        m = VALUE_RE.search(raw)
        current_value = m.group(1).lower() if m else None
        read_ok = current_value is not None

        if read_ok:
            ok_count += 1
        else:
            fail_count += 1

        changed_last, changed_baseline, suspected_fp = upsert_verification(conn, target, current_value, read_ok)

        tag = target["reg_name"]
        if changed_last:
            changed_last_list.append((tag, hex(addr)))
        if changed_baseline:
            changed_baseline_list.append((tag, hex(addr)))
        if suspected_fp:
            false_positive_list.append((tag, hex(addr)))

        if (i + 1) % 25 == 0 or (i + 1) == len(targets):
            update_test_progress(
                test_id,
                f"Progresso reteste ({i + 1}/{len(targets)})",
                f"OK={ok_count} FALHA={fail_count} suspeitos_ate_agora={len(false_positive_list)}"
            )

    conn.close()
    s.close()

    summary_lines = [
        f"Total resolvido/testado: {len(targets)} (pulados sem endereço: {len(skipped)})",
        f"Leituras OK: {ok_count} | Leituras com FALHA: {fail_count}",
        f"Mudaram desde o último reteste: {len(changed_last_list)}",
        f"Mudaram em relação ao valor-baseline original: {len(changed_baseline_list)}",
        f"SUSPEITOS DE FALSO POSITIVO (safe_to_read=1 antes, falha agora): {len(false_positive_list)}",
    ]
    if false_positive_list:
        summary_lines.append("Lista de suspeitos:")
        summary_lines.extend(f"  - {name} @ {addr}" for name, addr in false_positive_list)

    full_summary = "\n".join(summary_lines)
    status_final = "OK_NO_FALSE_POSITIVES" if not false_positive_list else "WARN_FALSE_POSITIVES_FOUND"
    update_test_progress(test_id, "Reteste Read-Only Concluído", full_summary, status=status_final)

    print("\n" + "=" * 60)
    print(full_summary)
    print("=" * 60)

    print("\nExecutando capture_dmesg.py para gerar dmesg.log local...")
    run_capture_dmesg()

    print(f"\nRETESTE CONCLUÍDO (ID: {test_id}, STATUS: {status_final})")


if __name__ == "__main__":
    main()
