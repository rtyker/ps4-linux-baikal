#!/usr/bin/env python3
"""
Busca por REFERENCIAS DE DADOS (ponteiro cru de 8 bytes) aos enderecos
0xffffffffdc9a3de7 (função que chama g_crypt_create_provider) e
0xffffffffdc9a40d0 (g_crypt_create_provider), para localizar a struct
g_class do GEOM_CRYPT (contendo os ponteiros taste/start/access/orphan/
destroy) e a partir dela achar a função "taste" (que lê os metadados
on-disk da partição, incluindo a flag em +0x70 usada para escolher a
chave).
"""
import os
os.environ["GHIDRA_INSTALL_DIR"] = "/ghidra"
import struct
import pyghidra
from pyghidra import open_project, consume_program

PROJECT_PATH = "/workspace/consolidado/tools/ghidra_project"
PROJECT_NAME = "orbis_mts"
PROGRAM_PATH = "/kmem_dump_1252.bin"

TARGETS = [0xffffffffdc9a3de7, 0xffffffffdc9a40d0]

def main():
    if not pyghidra.started():
        pyghidra.start()
    project = open_project(PROJECT_PATH, PROJECT_NAME, create=False)
    program, consumer = consume_program(project, PROGRAM_PATH)
    mem = program.getMemory()

    print("=" * 70)
    print("Searching for raw 8-byte pointer references (data xrefs)")
    print("=" * 70)

    for target in TARGETS:
        print(f"\n--- target 0x{target:016x} ---")
        target_bytes = struct.pack('<Q', target)
        count = 0
        for b in mem.getBlocks():
            if not b.isInitialized():
                continue
            try:
                size = b.getSize()
                if size > 40 * 1024 * 1024:
                    continue
                data = bytearray(size)
                mem.getBytes(b.getStart(), data)
            except Exception:
                continue
            start_off = b.getStart().getOffset()
            idx = 0
            while True:
                idx = data.find(target_bytes, idx)
                if idx == -1:
                    break
                found_va = start_off + idx
                print(f"  [FOUND] block={b.getName()} offset_in_block=0x{idx:x} VA=0x{found_va & 0xffffffffffffffff:016x}")
                count += 1
                idx += 1
        print(f"  total matches: {count}")

if __name__ == "__main__":
    main()
