#!/usr/bin/env python3
"""Busca referencias de codigo (LEA RIP-relative) a tabela de GUIDs de tipo
de particao encontrada em file offset 0x1a6d800 de memoriateste.bin."""
import os, struct
os.environ["GHIDRA_INSTALL_DIR"] = "/ghidra"
import pyghidra
from pyghidra import open_project, consume_program

PROJECT_PATH = "/workspace/consolidado/tools/ghidra_project"
PROJECT_NAME = "orbis_mts"
PROGRAM_PATH = "/kmem_dump_1252.bin"

TABLE_FILE_OFFSET = 0x1a6d800
TABLE_SIZE = 16 * 16  # 16 GUIDs de 16 bytes cada, testar tb janela maior

def main():
    if not pyghidra.started():
        pyghidra.start()
    project = open_project(PROJECT_PATH, PROJECT_NAME, create=False)
    program, consumer = consume_program(project, PROGRAM_PATH)
    mem = program.getMemory()
    base_va = program.getImageBase().getOffset()
    if base_va < 0:
        base_va += 1 << 64

    print(f"Image base: 0x{base_va:016x}")
    table_va = base_va + TABLE_FILE_OFFSET
    print(f"Table VA (hipotese file_offset==va-base): 0x{table_va:016x}")

    # Scan all initialized+executable blocks for LEA targeting any address
    # within [table_va, table_va+TABLE_SIZE+0x200] (some margin for entry offsets)
    lo = table_va - 0x20
    hi = table_va + TABLE_SIZE + 0x200
    print(f"Searching for LEA targets in [0x{lo:x}, 0x{hi:x}]")

    hits = []
    for b in mem.getBlocks():
        if not b.isExecute() or not b.isInitialized():
            continue
        size = b.getSize()
        if size > 25 * 1024 * 1024:
            continue
        try:
            data = bytearray(size)
            mem.getBytes(b.getStart(), data)
        except Exception:
            continue
        start_off = b.getStart().getOffset()
        if start_off < 0:
            start_off += 1 << 64
        n = len(data)
        for instr_len in (7, 6):
            disp_off = instr_len - 4
            for i in range(n - instr_len + 1):
                disp_pos = i + disp_off
                disp32 = struct.unpack_from('<i', data, disp_pos)[0]
                instr_addr = start_off + i
                computed = instr_addr + instr_len + disp32
                if lo <= computed <= hi:
                    b0 = data[i]
                    b1 = data[i+1] if i+1 < n else 0
                    is_lea = (instr_len == 7 and b0 in (0x48, 0x4c) and b1 == 0x8d) or (instr_len == 6 and b0 == 0x8d)
                    if is_lea:
                        hits.append((instr_addr, computed))
    print(f"Total LEA hits: {len(hits)}")
    for addr, target in sorted(hits):
        entry_idx = (target - table_va) // 16
        print(f"  LEA at 0x{addr:016x} -> target 0x{target:016x} (table entry ~#{entry_idx})")

if __name__ == "__main__":
    main()
