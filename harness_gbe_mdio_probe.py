#!/usr/bin/env python3
"""
harness_gbe_mdio_probe.py — Sonda o PHY da GBE Baikal (MTS) via MDIO/SMI
Clause 45, usando o registrador MDIO do MAC que acabamos de habilitar.

Objetivo: VALIDAR o bring-up. Se o MAC está de fato funcional depois do enable
(BAR0+0x34/0x38, Fase 14), uma transação MDIO deve completar e devolver um ID
de PHY plausível. Isso seria confirmação POSITIVA — hoje só sabemos que
registradores mudaram, não que o MAC opera.

PROTOCOLO (transcrito de `decompiled_dc5a2680.txt`, rotina MDIO do Orbis):

    reg_mdio = BAR0 + 0x00        (sem offset adicional: *(*(softc+0x3068)+0x10))

    out(reg_mdio, 0x8000)                                  # limpa busy
    cmd  = (arg & 0xffff0000) | ((arg & 0x1f) << 8) | 0x20  # fase de endereco
    out(reg_mdio, cmd)
    poll: le reg_mdio como int16; pronto quando < 0 (bit 15 do half baixo)
    out(reg_mdio, 0x8000)                                  # limpa busy
    out(reg_mdio, ((arg & 0x1f) << 8) | 0xe0)              # fase de leitura
    poll de novo
    resultado = valor >> 16

    Formato do arg: [31:16] = endereco do registrador do PHY, [4:0] = devad.

Confirmado por leitura: a GBE tem APENAS a BAR0 (4 KB) — `resource` e
`/proc/iomem` não mostram nenhuma outra região —, então o recurso do MDIO é
necessariamente essa BAR.

SEGURANÇA: escreve só em BAR0+0x00, que é o próprio registrador de comando
MDIO (uso normal dele). Não toca em reset, DMA ou Bus Master. Cada escrita é
verificada via mmio_write.parse_write_result — se não for confirmada, aborta.

Grava em test_history (Fase 15) e write_sweep_results (block_label='MDIO_PROBE').
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
MDIO_REG = BAR0_BASE + 0x00

# (devad, reg, descricao)
# Clause 45: devad 1 = PMA/PMD, regs 2/3 = PHY Identifier 1/2 (OUI do fabricante).
# devad 30/31 = vendor specific 1/2, usados pela rotina de calibracao do Orbis.
ALVOS = [
    (0x01, 0x0002, "PMA/PMD PHY Identifier 1 (OUI alto)"),
    (0x01, 0x0003, "PMA/PMD PHY Identifier 2 (OUI baixo + modelo/rev)"),
    (0x01, 0x0000, "PMA/PMD Control 1"),
    (0x01, 0x0001, "PMA/PMD Status 1"),
    (0x03, 0x0002, "PCS PHY Identifier 1"),
    (0x07, 0x0002, "AN PHY Identifier 1"),
    (0x1E, 0x0000, "Vendor Specific 1 reg 0x0000"),
    (0x1F, 0x0000, "Vendor Specific 2 reg 0x0000"),
]

DWORD_RE = re.compile(r'\b([0-9a-fA-F]{8})\b')


# ---------------- SQLite ----------------

def create_test_record(phase, test_name, target, initial_action):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO test_history (timestamp, phase, test_name, target_component, action_taken, status, complementary_info)
    VALUES (?, ?, ?, ?, ?, 'PENDING', 'Inicializando sonda MDIO...');
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


def log_mdio(devad, reg, desc, raw_final, resultado, pronto, notes):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
    INSERT INTO write_sweep_results
        (address, reg_name, block_label, value_before, value_written, value_after_immediate,
         value_after_settle, ping_ok, telnet_ok, ip_link_snapshot, result, timestamp, notes)
    VALUES (?, ?, 'MDIO_PROBE', NULL, ?, ?, ?, 1, 1, NULL, ?, ?, ?);
    """, (hex(MDIO_REG), f"MDIO devad={devad:#04x} reg={reg:#06x}",
          f"devad={devad:#04x} reg={reg:#06x}", raw_final,
          f"{resultado:#06x}" if resultado is not None else None,
          "PRONTO" if pronto else "TIMEOUT_OU_SEM_RESPOSTA", ts,
          f"{desc} | {notes}"))
    conn.commit()
    conn.close()


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


def run_cmd(s, cmd, wait=0.35, timeout=12):
    s.sendall(cmd.encode('ascii') + b"\n")
    time.sleep(wait)
    return read_until_prompt(s, timeout=timeout).decode('ascii', errors='replace')


def read_mdio_reg(s):
    raw = run_cmd(s, f"dd if=/dev/mem bs=4 count=1 skip=$(( {hex(MDIO_REG)} / 4 )) 2>/dev/null | od -An -tx4", wait=0.2)
    m = DWORD_RE.search(raw)
    return m.group(1) if m else None


def check_ping():
    try:
        return subprocess.run(["ping", "-c", "1", "-W", "2", PS4_IP],
                              capture_output=True, timeout=5).returncode == 0
    except Exception:
        return False


def escrever(s, valor, rotulo):
    """Escreve no registrador MDIO, com verificação obrigatória."""
    saida = run_cmd(s, build_write_cmd(MDIO_REG, valor), wait=0.35)
    ok, det = parse_write_result(saida)
    if not ok:
        print(f"    !!! escrita NAO ocorreu ({rotulo}): {det}")
    return ok, det


def mdio_read(s, devad, reg):
    """Uma leitura MDIO Clause 45 completa. Retorna (resultado, pronto, trilha)."""
    trilha = []

    # fase de endereço
    ok, det = escrever(s, 0x00008000, "clear busy 1")
    if not ok:
        return None, False, [f"falha clear busy 1: {det}"]

    cmd_addr = ((reg & 0xFFFF) << 16) | ((devad & 0x1F) << 8) | 0x20
    ok, det = escrever(s, cmd_addr, "fase de endereco")
    if not ok:
        return None, False, [f"falha fase de endereco: {det}"]

    v1 = read_mdio_reg(s)
    trilha.append(f"pos-endereco={v1}")
    pronto1 = bool(v1 and (int(v1, 16) & 0x8000))

    # fase de leitura
    ok, det = escrever(s, 0x00008000, "clear busy 2")
    if not ok:
        return None, False, trilha + [f"falha clear busy 2: {det}"]

    cmd_read = ((devad & 0x1F) << 8) | 0xE0
    ok, det = escrever(s, cmd_read, "fase de leitura")
    if not ok:
        return None, False, trilha + [f"falha fase de leitura: {det}"]

    v2 = read_mdio_reg(s)
    trilha.append(f"pos-leitura={v2}")
    if not v2:
        return None, False, trilha

    val = int(v2, 16)
    pronto2 = bool(val & 0x8000)
    resultado = (val >> 16) & 0xFFFF
    trilha.append(f"pronto_addr={pronto1} pronto_read={pronto2}")
    return resultado, pronto2, trilha


def main():
    print("=" * 78)
    print("SONDA MDIO (Clause 45) — o MAC habilitado consegue falar com o PHY?")
    print("=" * 78)

    test_id = create_test_record(
        "Fase 15",
        "Sonda MDIO Clause 45 no PHY da GBE (valida o bring-up da Fase 14)",
        f"Registrador MDIO em {hex(MDIO_REG)} (BAR0+0x00)",
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

    estado_inicial = read_mdio_reg(s)
    print(f"\nEstado inicial do registrador MDIO ({hex(MDIO_REG)}): {estado_inicial}")
    if estado_inicial:
        v = int(estado_inicial, 16)
        print(f"  decodificado: dado={v >> 16:#06x}  busy/pronto(bit15)={'1' if v & 0x8000 else '0'}  baixo={v & 0xffff:#06x}")
    update_test_progress(test_id, "Estado inicial do MDIO", f"{hex(MDIO_REG)} = {estado_inicial}")

    print(f"\n{'devad':>6} {'reg':>8} {'resultado':>10} {'pronto':>7}  descricao")
    print("-" * 78)

    resultados = []
    for devad, reg, desc in ALVOS:
        resultado, pronto, trilha = mdio_read(s, devad, reg)
        raw_final = trilha[-2] if len(trilha) >= 2 else (trilha[-1] if trilha else None)
        res_txt = f"{resultado:#06x}" if resultado is not None else "----"
        print(f"{devad:>#6x} {reg:>#8x} {res_txt:>10} {str(pronto):>7}  {desc}")
        log_mdio(devad, reg, desc, str(raw_final), resultado, pronto, " ; ".join(trilha))
        resultados.append((devad, reg, desc, resultado, pronto))

        if not check_ping():
            update_test_progress(test_id, "ABORTADO — perda de ping",
                                 f"parou em devad={devad:#x} reg={reg:#x}",
                                 status="ABORTED_PING_LOST")
            print("\n!!! ABORTADO — sem ping !!!")
            s.close()
            return

    s.close()

    # --- Veredito ---
    # CORRIGIDO 2026-07-22: a versão anterior desta lógica produziu FALSO POSITIVO.
    # Ela só checava (res != 0x0000 and res != 0xffff) e declarou "bring-up validado"
    # quando os 8 alvos devolveram o MESMO 0x7949 — que era resíduo já presente no
    # registrador ANTES de qualquer transação. Duas exigências novas, ambas
    # necessárias para uma leitura MDIO ser considerada real:
    #   (a) o dado tem que DIFERIR do valor que já estava no registrador; e
    #   (b) alvos diferentes têm que devolver valores DIFERENTES entre si —
    #       PHY ID1/ID2/Control/Status não podem ter conteúdo idêntico.
    residuo_inicial = (int(estado_inicial, 16) >> 16) & 0xFFFF if estado_inicial else None

    obtidos = [res for _, _, _, res, _ in resultados if res is not None]
    distintos = set(obtidos)
    iguais_ao_residuo = [res for res in obtidos if res == residuo_inicial]

    validos = [(d, r, desc, res) for d, r, desc, res, _pronto in resultados
               if res is not None and res not in (0x0000, 0xFFFF) and res != residuo_inicial]
    prontos = [x for x in resultados if x[4]]

    if len(distintos) <= 1 and obtidos:
        veredito = (f"FALSO POSITIVO EVITADO: todos os {len(obtidos)} alvos devolveram o MESMO "
                    f"valor ({next(iter(distintos)):#06x}). Registradores diferentes do PHY não podem "
                    f"ter conteúdo idêntico — a transação MDIO NÃO completou. "
                    f"{'O valor é o resíduo pré-existente no registrador.' if iguais_ao_residuo else ''}")
        status = "MDIO_VALOR_UNICO_TRANSACAO_NAO_COMPLETOU"
    elif validos and len(distintos) > 1:
        veredito = (f"MDIO RESPONDEU: {len(validos)} alvos com dado distinto do resíduo inicial "
                    f"({residuo_inicial:#06x}) e {len(distintos)} valores diferentes entre si. "
                    f"O MAC habilitado fala com o PHY — bring-up VALIDADO.")
        status = "MDIO_OK_PHY_RESPONDE"
    elif prontos:
        veredito = (f"MDIO sinalizou pronto em {len(prontos)} alvos, mas sem dado utilizável "
                    f"(0x0000/0xffff ou igual ao resíduo). Transação não produziu leitura real.")
        status = "MDIO_PRONTO_SEM_DADO"
    else:
        veredito = ("MDIO não sinalizou pronto em nenhum alvo — a transação não completa. "
                    "O MAC não está operando o barramento MDIO.")
        status = "MDIO_SEM_RESPOSTA"

    print("\n" + "=" * 78)
    print(veredito)
    print("=" * 78)
    if validos:
        print("\nAlvos com dado plausível:")
        for d, r, desc, res in validos:
            print(f"  devad={d:#04x} reg={r:#06x} -> {res:#06x}   {desc}")

    update_test_progress(test_id, "Sonda MDIO concluída", veredito, status=status)


if __name__ == "__main__":
    main()
