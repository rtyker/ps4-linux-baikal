#!/usr/bin/env python3
"""
mmio_write.py — Módulo único e oficial de ESCRITA MMIO do projeto.

MOTIVO (2026-07-22): todos os harnesses escreviam com `devmem <addr> 32 <val> 2>/dev/null`.
O comando `devmem` **NÃO EXISTE** neste sistema (nem binário, nem applet do busybox — exit 127),
e o `2>/dev/null` mascarava o erro. Resultado: nenhuma escrita jamais chegou ao hardware, e
vários testes foram reportados como "sem efeito" sem que nada tivesse sido escrito.
Ver memory/devmem-nao-existe-usar-dd-octal.md.

MÉTODO CORRETO (medido funcionando):
    printf '\\001\\000\\000\\000' | dd of=/dev/mem bs=4 count=1 seek=$((ADDR/4))
    -> 1+0 records in / 1+0 records out / 4 bytes copied / exit=0

Escaping OCTAL (`\\NNN`), nunca hexadecimal (`\\xHH`) — o `\\xHH` não é confiável via telnet,
conforme memory/escrita-mmio-telnet-printf-octal-nao-hex.md.
Ordem dos bytes é little-endian: 0xAABBCCDD vira '\\DDD\\CCC\\BBB\\AAA'.

Uso:
    from mmio_write import build_write_cmd, parse_write_result
    cmd = build_write_cmd(0xc2000034, 0x00000001)
    saida = run_cmd(s, cmd)
    ok, detalhe = parse_write_result(saida)
    if not ok:
        # NUNCA tratar como "sem efeito" — a escrita nao ocorreu
        ...
"""

import re

# "1+0 records out" e "4 bytes (4B) copied" sao a prova de que a escrita ocorreu
RECORDS_OUT_RE = re.compile(r'(\d+)\+(\d+)\s+records out')
BYTES_COPIED_RE = re.compile(r'(\d+)\s+bytes?\s*(?:\([^)]*\))?\s*copied')
EXIT_RE = re.compile(r'exit=(\d+)')


def to_octal_le(value, nbytes=4):
    """0xAABBCCDD -> '\\DDD\\CCC\\BBB\\AAA' (little-endian, escaping octal)."""
    value &= (1 << (8 * nbytes)) - 1
    out = []
    for i in range(nbytes):
        b = (value >> (8 * i)) & 0xFF
        out.append(f"\\{b:03o}")
    return "".join(out)


def build_write_cmd(addr, value, nbytes=4):
    """Monta o comando de escrita MMIO. stderr NAO e suprimido de proposito:
    a saida do dd e a unica prova de que a escrita aconteceu."""
    octal = to_octal_le(value, nbytes)
    return (f"printf '{octal}' | dd of=/dev/mem bs={nbytes} count=1 "
            f"seek=$(( {hex(addr)} / {nbytes} )) 2>&1; echo exit=$?")


def parse_write_result(output):
    """Confere que a escrita realmente ocorreu.
    Retorna (ok: bool, detalhe: str)."""
    if "not found" in output or "applet not found" in output:
        return False, "COMANDO INEXISTENTE (not found) — escrita NAO ocorreu"

    m_exit = EXIT_RE.search(output)
    exit_code = int(m_exit.group(1)) if m_exit else None
    if exit_code not in (0, None):
        return False, f"exit={exit_code} — escrita NAO ocorreu"

    m_rec = RECORDS_OUT_RE.search(output)
    m_bytes = BYTES_COPIED_RE.search(output)
    if not m_rec and not m_bytes:
        return False, "sem 'records out'/'bytes copied' — escrita NAO confirmada"

    detalhe = []
    if m_rec:
        detalhe.append(f"records out={m_rec.group(1)}+{m_rec.group(2)}")
        if m_rec.group(1) == "0":
            return False, "records out=0 — escrita NAO ocorreu"
    if m_bytes:
        detalhe.append(f"bytes copied={m_bytes.group(1)}")
    if exit_code is not None:
        detalhe.append(f"exit={exit_code}")
    return True, " | ".join(detalhe)


def build_read_cmd(addr, nbytes=4):
    """Leitura MMIO (esta sempre funcionou — dd + od)."""
    return (f"dd if=/dev/mem bs={nbytes} count=1 skip=$(( {hex(addr)} / {nbytes} )) "
            f"2>/dev/null | od -An -tx{nbytes}")


if __name__ == "__main__":
    # autoteste do encoding, sem tocar em hardware
    casos = [
        (0x00000001, "\\001\\000\\000\\000"),
        (0x00000400, "\\000\\004\\000\\000"),
        (0x017D7840, "\\100\\170\\175\\001"),
        (0xAABBCCDD, "\\335\\314\\273\\252"),
    ]
    print("autoteste de encoding octal little-endian:")
    ok = True
    for val, esperado in casos:
        got = to_octal_le(val)
        status = "OK " if got == esperado else "FALHA"
        if got != esperado:
            ok = False
        print(f"  {status} 0x{val:08X} -> {got}   (esperado {esperado})")
    print("\nexemplo de comando gerado:")
    print("  " + build_write_cmd(0xc2000034, 1))
    print("\nautoteste do parser:")
    for saida, esperado_ok in [
        ("1+0 records in\n1+0 records out\n4 bytes (4B) copied\nexit=0", True),
        ("/bin/sh: devmem: not found\nexit=127", False),
        ("0+0 records out\nexit=0", False),
        ("exit=1", False),
    ]:
        got_ok, det = parse_write_result(saida)
        status = "OK " if got_ok == esperado_ok else "FALHA"
        if got_ok != esperado_ok:
            ok = False
        print(f"  {status} ok={got_ok:<5} {det}")
    print("\nRESULTADO:", "todos passaram" if ok else "HOUVE FALHA")
