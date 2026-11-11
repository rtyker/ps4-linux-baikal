#!/usr/bin/env python3
"""
Rastreia a origem da flag de seleção de chave (offset +0x70) usada por
g_crypt_create_provider (0xffffffffdc9a40d0). Expande callers a partir de
g_crypt_start_disk (0xffffffffdc9a3de7) em profundidade (até 3 níveis) para
achar a função que popula essa flag a partir dos metadados de partição
(APA/EAP), com o objetivo de descobrir se ela difere por número de partição
(sda13 vs sda27).
"""

import os

os.environ["GHIDRA_INSTALL_DIR"] = "/ghidra"

import pyghidra
from pyghidra import open_project, consume_program

PROJECT_PATH = "/workspace/consolidado/tools/ghidra_project"
PROJECT_NAME = "orbis_mts"
PROGRAM_PATH = "/kmem_dump_1252.bin"
OUT_DIR = "/workspace/consolidado/decompiled/geom_crypt"

SEED_ADDRS = [0xdc9a40d0, 0xdc9a3de7]  # g_crypt_create_provider, g_crypt_start_disk
MAX_DEPTH = 3


def find_prologue(mem, start_va):
    """Walk backwards up to 4KB for push rbp (0x55 0x48 0x89 0xe5) or endbr64 (0xf3 0x0f 0x1e 0xfa)."""
    start_off = start_va.getOffset()
    space = start_va.getAddressSpace()
    for back in range(0, 4096):
        try:
            cand = space.getAddress(start_off - back)
            b0 = mem.getByte(cand) & 0xff
            if b0 == 0x55:
                b1 = mem.getByte(cand.add(1)) & 0xff
                b2 = mem.getByte(cand.add(2)) & 0xff
                b3 = mem.getByte(cand.add(3)) & 0xff
                if b1 == 0x48 and b2 == 0x89 and b3 == 0xe5:
                    return cand
            elif b0 == 0xf3:
                b1 = mem.getByte(cand.add(1)) & 0xff
                b2 = mem.getByte(cand.add(2)) & 0xff
                b3 = mem.getByte(cand.add(3)) & 0xff
                if b1 == 0x0f and b2 == 0x1e and b3 == 0xfa:
                    return cand
        except Exception:
            pass
    return None


def main():
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)

    if not pyghidra.started():
        pyghidra.start()

    project = open_project(PROJECT_PATH, PROJECT_NAME, create=False)
    program, consumer = consume_program(project, PROGRAM_PATH)

    from ghidra.util.task import ConsoleTaskMonitor
    from ghidra.app.decompiler import DecompInterface, DecompileOptions
    from ghidra.app.cmd.disassemble import DisassembleCommand
    from ghidra.app.cmd.function import CreateFunctionCmd
    from ghidra.program.model.address import AddressSet

    monitor = ConsoleTaskMonitor()
    fm = program.getFunctionManager()
    listing = program.getListing()
    addr_factory = program.getAddressFactory()
    default_space = addr_factory.getDefaultAddressSpace()
    base_va = program.getImageBase().getOffset()
    # base_va corresponds to 0xffffffffdc350000; low32 = 0xdc350000
    base_low32 = 0xdc350000

    print("=" * 70)
    print("Trace partition-flag origin (callers of g_crypt_start_disk)")
    print(f"Program: {program.getName()}, Base: {program.getImageBase()}")
    print("=" * 70)

    mem = program.getMemory()
    seeds = []
    all_funcs = list(fm.getFunctions(True))
    tx_id = program.startTransaction("seed functions")
    try:
        for a in SEED_ADDRS:
            f = None
            for cand in all_funcs:
                if (cand.getEntryPoint().getOffset() & 0xffffffff) == a:
                    f = cand
                    break
            if f is None:
                offset = a - base_low32
                raw_va = default_space.getAddress(base_va + offset)
                prologue = find_prologue(mem, raw_va)
                va = prologue if prologue is not None else raw_va
                print(f"  no existing function at 0x{a:x} (raw {raw_va}), prologue found at {va} ...")
                if listing.getInstructionAt(va) is None:
                    dcmd = DisassembleCommand(va, AddressSet(va, va.add(4096)), False)
                    dcmd.applyTo(program, monitor)
                cmd = CreateFunctionCmd(va)
                if cmd.applyTo(program, monitor):
                    f = fm.getFunctionAt(va)
                else:
                    print(f"  [WARN] CreateFunctionCmd failed: {cmd.getStatusMsg()}")
            if f is None:
                print(f"  [WARN] STILL no function at 0x{a:x}")
                continue
            seeds.append(f)
            print(f"  seed: 0x{a:x} {f.getName()} @ {f.getEntryPoint()}")
    finally:
        program.endTransaction(tx_id, True)

    # BFS upward (callers only) up to MAX_DEPTH
    visited = set(seeds)
    frontier = list(seeds)
    depth = 0
    while frontier and depth < MAX_DEPTH:
        depth += 1
        next_frontier = []
        for f in frontier:
            try:
                callers = list(f.getCallingFunctions(monitor))
            except Exception:
                callers = []
            for c in callers:
                if c not in visited:
                    visited.add(c)
                    next_frontier.append(c)
                    print(f"  [DEPTH {depth}] caller: 0x{c.getEntryPoint().getOffset():016x} {c.getName()}")
        frontier = next_frontier

    print(f"\nTotal functions to decompile: {len(visited)}")

    decomp = DecompInterface()
    opts = DecompileOptions()
    opts.setDefaultTimeout(120)
    decomp.setOptions(opts)
    decomp.openProgram(program)

    extracted = 0
    failed = 0
    summary_path = os.path.join(OUT_DIR, "_CALLERS_SUMMARY.txt")
    with open(summary_path, "w") as sum_f:
        sum_f.write("Callers of g_crypt_start_disk / g_crypt_create_provider (BFS up to depth 3)\n")
        sum_f.write("=" * 70 + "\n\n")

        for f in sorted(visited, key=lambda x: x.getEntryPoint().getOffset()):
            entry = f.getEntryPoint()
            addr_int = entry.getOffset()
            short_name = f"{addr_int & 0xffffffff:08x}"
            out_file = os.path.join(OUT_DIR, f"decompiled_{short_name}_{f.getName()}.c")

            try:
                res = decomp.decompileFunction(f, 120, monitor)
                if res and res.decompileCompleted():
                    src = res.getDecompiledFunction().getC()
                    callers = list(f.getCallingFunctions(monitor))
                    callees = list(f.getCalledFunctions(monitor))
                    with open(out_file, "w") as fh:
                        fh.write("// Extracted by PyGhidra (trace_partition_flag_origin.py)\n")
                        fh.write(f"// addr: 0x{addr_int:016x}  name: {f.getName()}\n")
                        fh.write(f"// callers ({len(callers)}):\n")
                        for c in callers[:15]:
                            fh.write(f"//   {c.getName()} @ 0x{c.getEntryPoint().getOffset():016x}\n")
                        fh.write(f"// callees ({len(callees)}):\n")
                        for c in callees[:15]:
                            fh.write(f"//   {c.getName()} @ 0x{c.getEntryPoint().getOffset():016x}\n")
                        fh.write("\n")
                        fh.write(src)
                    extracted += 1
                    print(f"  [OK] 0x{addr_int:016x} {f.getName()} -> {os.path.basename(out_file)}")
                    sum_f.write(f"0x{addr_int:016x}  {f.getName()}\n")
                else:
                    failed += 1
                    print(f"  [DECOMP-FAIL] 0x{addr_int:016x} {f.getName()}")
                    sum_f.write(f"0x{addr_int:016x}  {f.getName()}  [DECOMP-FAIL]\n")
            except Exception as e:
                failed += 1
                print(f"  [EXC] 0x{addr_int:016x} {f.getName()} - {e}")

    decomp.dispose()
    print("=" * 70)
    print(f"FINISHED: Extracted={extracted}, Failed={failed}, Summary={summary_path}")
    print("=" * 70)


if __name__ == "__main__":
    main()
