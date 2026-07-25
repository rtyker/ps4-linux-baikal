#!/usr/bin/env python3
"""
Gera consolidado/decompiled/CROSSREF.md com call-graph das funcoes MTS/GBE/ICC/glue.
Combina dados do SQLite (decompiled_functions) com parse dos arquivos extracted/*.txt.
"""
import os
import re
import sqlite3
import glob

DB_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db"
EXTRACTED_DIR = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/decompiled/extracted"
EXISTING_DIRS = [
    "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/decompiled",
    "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/decompiled/legacy_raiz",
]
OUT = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/decompiled/CROSSREF.md"

# Regex para cabeçalhos do PyGhidra extraction
RE_CALLERS = re.compile(r"^// chamadores \((\d+)\):$")
RE_CALLEES = re.compile(r"^// chamadas \((\d+)\):$")
RE_REF = re.compile(r"^//\s+([^\s]+) @ 0x([0-9a-f-]+)$")

def parse_callers_callees(path):
    """Devolve (callers, callees) como listas de (name, addr)."""
    callers, callees = [], []
    if not os.path.exists(path):
        return callers, callees
    cur_section = None
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            m_c = RE_CALLERS.match(line)
            m_e = RE_CALLEES.match(line)
            if m_c:
                cur_section = "callers"
                continue
            if m_e:
                cur_section = "callees"
                continue
            if line.startswith("//"):
                m = RE_REF.match(line)
                if m and cur_section in ("callers", "callees"):
                    name, addr_hex = m.group(1), m.group(2)
                    # addr_hex pode ser negativo
                    try:
                        if addr_hex.startswith("-"):
                            addr = int(addr_hex, 16) + (1 << 64)
                        else:
                            addr = int(addr_hex, 16)
                    except Exception:
                        continue
                    entry = (name, addr & 0xffffffffffffffff)
                    if cur_section == "callers":
                        callers.append(entry)
                    else:
                        callees.append(entry)
                continue
            if line.strip() == "":
                cur_section = None
    return callers, callees

def short_addr(addr):
    s = "%016x" % addr
    return s[-8:]

def main():
    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()
    cur.execute("SELECT addr_hex, addr_full, short_name, category, role, file_path, status FROM decompiled_functions ORDER BY addr_hex")
    funcs = cur.fetchall()
    con.close()

    # Map short_name -> (category, role, file_path, status)
    name_map = {}
    for addr_hex, _, _, category, role, file_path, status in funcs:
        name_map[addr_hex] = (category, role, file_path, status)

    # Para cada extracted file busca callers/callees
    callgraph = {}  # short -> (callers, callees)
    for fpath in glob.glob(os.path.join(EXTRACTED_DIR, "decompiled_*.txt")):
        callers, callees = parse_callers_callees(fpath)
        # short name do arquivo = filename sem prefix e .txt
        short = os.path.basename(fpath).replace("decompiled_", "").replace(".txt", "")
        callgraph[short] = (callers, callees)

    # Gera markdown
    out = ["# Call-Graph de Funções MTS/GBE/ICC/glue",
           "",
           "> Gerado automaticamente por `consolidado/tools/gen_crossref.py` a partir de:",
           "> - `consolidado/ps4_hardware_memory.db` → tabela `decompiled_functions`",
           "> - `consolidado/decompiled/extracted/*.txt` → header com callers/callees",
           ">",
           "> Cada função lista seus chamadores (quem a chama) e suas chamadas (quem ela chama).",
           "> Endereços em formato curto (`dc5a0070`).",
           "",
           "## Resumo de cobertura",
           "",
           "| Categoria | Total | Bruto | Revisado | Refutado |",
           "|---|---|---|---|---|",
           ]

    con = sqlite3.connect(DB_PATH)
    cur = con.cursor()
    cur.execute("""
        SELECT category, status, COUNT(*) FROM decompiled_functions
        GROUP BY category, status ORDER BY category, status
    """)
    by_cat = {}
    for cat, st, cnt in cur.fetchall():
        by_cat.setdefault(cat, {})[st] = cnt
    con.close()

    cats_sorted = sorted(by_cat.keys())
    for cat in cats_sorted:
        totals = by_cat[cat]
        total = sum(totals.values())
        out.append(f"| {cat} | {total} | {totals.get('bruto', 0)} | {totals.get('revisado', 0)} | {totals.get('refutado', 0)} |")

    out.append("")
    out.append("## Call-graph por função")
    out.append("")

    # Itera pelas funções do extracted
    for short in sorted(callgraph.keys()):
        info = name_map.get(short, ("?", "?", "?", "?"))
        cat, role, fpath, status = info
        callers, callees = callgraph[short]
        out.append(f"### `{short}` — {status} — {cat}")
        out.append("")
        out.append(f"- **Papel**: {role}")
        out.append(f"- **Arquivo**: `{fpath}`")
        out.append("")
        if callers:
            out.append(f"- **Chamadores** ({len(callers)}):")
            for name, addr in callers:
                sa = short_addr(addr)
                cat_str = name_map.get(sa, ("?",)*4)[0]
                out.append(f"  - `{sa}` {name} ({cat_str})")
        else:
            out.append("- **Chamadores**: nenhum (registrado via callback - provável handler de IRQ/timer)")
        if callees:
            out.append(f"- **Chamadas** ({len(callees)}):")
            for name, addr in callees:
                sa = short_addr(addr)
                cat_str = name_map.get(sa, ("?",)*4)[0]
                out.append(f"  - `{sa}` {name} ({cat_str})")
        else:
            out.append("- **Chamadas**: nenhuma (leaf function - provavelmente I/O direto)")
        out.append("")

    # Total
    out.insert(9, f"| **TOTAL** | {sum(sum(v.values()) for v in by_cat.values())} |"
                  f" {sum(v.get('bruto', 0) for v in by_cat.values())} |"
                  f" {sum(v.get('revisado', 0) for v in by_cat.values())} |"
                  f" {sum(v.get('refutado', 0) for v in by_cat.values())} |")

    with open(OUT, "w") as f:
        f.write("\n".join(out))
    print(f"CROSSREF.md gerado em: {OUT}")
    print(f"Funcoes no call-graph: {len(callgraph)}")

main()
