#!/usr/bin/env python3
"""
Extração automatizada do pipeline de criptografia GEOM_CRYPT do kernel Orbis
usando PyGhidra via Docker container ghidra-py.

Mapeia strings de log GEOM_CRYPT e SBL, localiza instruções LEA / referências,
identifica prólogos de função (push rbp / endbr64), e decompila cada função.
"""

import os
import sys
import struct
import re

os.environ["GHIDRA_INSTALL_DIR"] = "/ghidra"

import pyghidra
from pyghidra import open_project, consume_program

PROJECT_PATH = "/workspace/consolidado/tools/ghidra_project"
PROJECT_NAME = "orbis_mts"
PROGRAM_PATH = "/kmem_dump_1252.bin"
OUT_DIR = "/workspace/consolidado/decompiled/geom_crypt"

TARGET_STRINGS = [
    "GEOM_CRYPT[%u]: eap key setup",
    "GEOM_CRYPT[%u]: applying eap key",
    "GEOM_CRYPT[%u]: applying XTS",
    "GEOM_CRYPT[%u]: applying main key 2",
    "GEOM_CRYPT[%u]: applying ext key",
    "SCE_EAP_HDD__KEY",
    "EAP_U00",
    "EAP_V00",
    "sceSblWrapHddEapPartitionKeyData",
    "sceSblGetEapInternalPartKeyAddSign",
    "sceSblAuthMgrAddEEkc ",
    "sceSblAuthMgrAddEEkc2",
    "sceSblAuthMgrAddEEkc3",
    "sceSblAuthMgrDeleteEEkc",
    "sceSblKeymgrSmCallfuncWithID",
    "sceSblKeymgrLockKey",
    "geom_crypt.c"
]

FALLBACK_OFFSETS = [
    0x00aee641, 0x00aee9af, 0x00aeea14, 0x00aee9ef, 0x00aee9d1,
    0x00ae7f30, 0x00aeb434, 0x00aeb474, 0x00aed53e, 0x00aed569,
    0x00aed4d6, 0x00aed510, 0x00ae8bc5, 0x00b17279, 0x00aee8f2
]

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

    mem = program.getMemory()
    listing = program.getListing()
    ref_mgr = program.getReferenceManager()
    fm = program.getFunctionManager()
    addr_factory = program.getAddressFactory()
    default_space = addr_factory.getDefaultAddressSpace()

    from ghidra.util.task import ConsoleTaskMonitor
    from ghidra.app.decompiler import DecompInterface, DecompileOptions
    from ghidra.app.cmd.disassemble import DisassembleCommand
    from ghidra.app.cmd.function import CreateFunctionCmd
    from ghidra.program.model.address import AddressSet

    monitor = ConsoleTaskMonitor()

    print("=" * 70)
    print("GEOM_CRYPT Extraction (PyGhidra)")
    print(f"Program: {program.getName()}, Base: {program.getImageBase()}")
    print("=" * 70)

    # Phase 1: String search via mem.findBytes
    string_vas = {}
    for target in TARGET_STRINGS:
        target_bytes = target.encode('ascii')
        string_vas[target] = []
        for b in mem.getBlocks():
            if not b.isInitialized(): continue
            addr = b.getStart()
            end = b.getEnd()
            while addr is not None and addr.compareTo(end) < 0:
                found = mem.findBytes(addr, end, target_bytes, None, True, monitor)
                if found is None: break
                string_vas[target].append(found)
                print(f"  [FOUND] '{target}' at VA {found}")
                addr = found.add(1)

    base_va = program.getImageBase().getOffset()
    # Add fallbacks
    for off in FALLBACK_OFFSETS:
        va = default_space.getAddress(base_va + off)
        found_any = False
        for vas in string_vas.values():
            if va in vas:
                found_any = True; break
        if not found_any:
            string_vas[f"fallback_0x{off:x}"] = [va]

    # Phase 2: Find code references (RIP-relative LEA scan + ReferenceManager)
    code_refs = {}  # string_name -> list of code VAs
    for target, vas in string_vas.items():
        code_refs[target] = set()
        for va in vas:
            # 1. Ghidra ReferenceManager
            try:
                refs = ref_mgr.getReferencesTo(va)
                for r in refs:
                    code_refs[target].add(r.getFromAddress())
            except Exception:
                pass

    # LEA scan on executable blocks
    va_to_name = {}
    for target, vas in string_vas.items():
        for va in vas:
            va_to_name[va.getOffset()] = target

    for b in mem.getBlocks():
        if not b.isExecute() or not b.isInitialized(): continue
        b_size = b.getSize()
        if b_size > 25 * 1024 * 1024: continue
        print(f"  Scanning executable block {b.getName()} ({b.getStart()}-{b.getEnd()})...")
        try:
            data = bytearray(b_size)
            mem.getBytes(b.getStart(), data)
        except Exception:
            continue

        b_start_off = b.getStart().getOffset()
        data_len = len(data)

        for str_va, target in va_to_name.items():
            for instr_len in (7, 6):
                disp_off = instr_len - 4
                for i in range(data_len - instr_len + 1):
                    disp_pos = i + disp_off
                    disp32 = struct.unpack_from('<i', data, disp_pos)[0]
                    instr_addr = b_start_off + i
                    computed = instr_addr + instr_len + disp32
                    if computed == str_va:
                        b0 = data[i]
                        b1 = data[i+1] if i+1 < data_len else 0
                        is_lea = (instr_len == 7 and b0 in (0x48, 0x4c) and b1 == 0x8d) or (instr_len == 6 and b0 == 0x8d)
                        if is_lea:
                            code_va = default_space.getAddress(instr_addr)
                            code_refs[target].add(code_va)

    total_code_refs = sum(len(v) for v in code_refs.values())
    print(f"Phase 2 complete: {total_code_refs} code references found across all strings")

    # Phase 3: Find function entry points
    func_entries = {}  # entry_VA -> set of string names
    for target, c_vas in code_refs.items():
        for c_va in c_vas:
            prologue = find_prologue(mem, c_va)
            if prologue:
                if prologue not in func_entries:
                    func_entries[prologue] = set()
                func_entries[prologue].add(target)

    # Also check string VAs directly in case prologues are immediately preceding
    for target, vas in string_vas.items():
        for va in vas:
            prologue = find_prologue(mem, va)
            if prologue:
                if prologue not in func_entries:
                    func_entries[prologue] = set()
                func_entries[prologue].add(target)

    print(f"Phase 3 complete: {len(func_entries)} unique function entry points identified")

    # Disassemble & create functions
    target_funcs = set()
    for entry, strings in func_entries.items():
        if listing.getInstructionAt(entry) is None:
            try:
                end = entry.add(2048)
                dcmd = DisassembleCommand(entry, AddressSet(entry, end), False)
                dcmd.applyTo(program, monitor)
            except Exception:
                pass

        f = fm.getFunctionAt(entry)
        if f is None:
            cmd = CreateFunctionCmd(entry)
            if cmd.applyTo(program, monitor):
                f = fm.getFunctionAt(entry)

        if f is not None:
            target_funcs.add(f)
            print(f"  [FUNC] 0x{entry.getOffset():016x} {f.getName()} (strings: {', '.join(strings)})")

    # Expand 1-level callers/callees
    expanded = set(target_funcs)
    for f in list(target_funcs):
        try:
            expanded.update(f.getCallingFunctions(monitor))
            expanded.update(f.getCalledFunctions(monitor))
        except Exception:
            pass

    print(f"Total functions to decompile (including callers/callees): {len(expanded)}")

    # Phase 4: Decompile
    decomp = DecompInterface()
    opts = DecompileOptions()
    opts.setDefaultTimeout(120)
    decomp.setOptions(opts)
    decomp.openProgram(program)

    extracted = 0
    failed = 0

    summary_path = os.path.join(OUT_DIR, "_SUMMARY.txt")
    with open(summary_path, "w") as sum_f:
        sum_f.write("======================================================================\n")
        sum_f.write("GEOM_CRYPT Extraction Summary (PyGhidra)\n")
        sum_f.write("======================================================================\n\n")

        for f in sorted(expanded, key=lambda x: x.getEntryPoint().getOffset()):
            entry = f.getEntryPoint()
            addr_int = entry.getOffset()
            short_name = f"{addr_int & 0xffffffff:08x}"
            out_file = os.path.join(OUT_DIR, f"decompiled_{short_name}_{f.getName()}.c")

            strings = func_entries.get(entry, set())
            is_direct = len(strings) > 0

            try:
                res = decomp.decompileFunction(f, 120, monitor)
                if res and res.decompileCompleted():
                    src = res.getDecompiledFunction().getC()
                    callers = list(f.getCallingFunctions(monitor))
                    callees = list(f.getCalledFunctions(monitor))

                    with open(out_file, "w") as fh:
                        fh.write("// Extracted by PyGhidra (consolidate_geom_crypt.py)\n")
                        fh.write(f"// addr: 0x{addr_int:016x}  name: {f.getName()}  size: {f.getBody().getNumAddresses()}\n")
                        fh.write(f"// type: {'DIRECT' if is_direct else 'INDIRECT'}\n")
                        if is_direct:
                            fh.write(f"// strings: {', '.join(sorted(strings))}\n")
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
                    sum_f.write(f"0x{addr_int:016x}  {f.getName()}  ({'DIRECT: ' + ', '.join(strings) if is_direct else 'INDIRECT'})\n")
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
