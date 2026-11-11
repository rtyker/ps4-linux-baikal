#!/usr/bin/env python3
"""
RE do trecho de codigo em g_part_gpt (0xffffffffdc8dabae) que aparentemente
seta pp->flags=1. Objetivo: achar o inicio real da funcao (prologo),
decompilar com decompilador (que resolve if/else automaticamente a partir
do CFG), E imprimir o disassembly bruto ao redor do endereco alvo mostrando
instrucoes de salto/branch para confirmar se a escrita e condicional.
"""
import os
os.environ["GHIDRA_INSTALL_DIR"] = "/ghidra"
import pyghidra
from pyghidra import open_project, consume_program

PROJECT_PATH = "/workspace/consolidado/tools/ghidra_project"
PROJECT_NAME = "orbis_mts"
PROGRAM_PATH = "/kmem_dump_1252.bin"
OUT_DIR = "/workspace/consolidado/decompiled/geom_crypt"

TARGET_FILE_OFFSET = None  # vamos calcular via VA direto abaixo
TARGET_VA_LOW32 = 0xdc8dabae


def find_prologue(mem, start_va):
    start_off = start_va.getOffset()
    space = start_va.getAddressSpace()
    for back in range(0, 8192):
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
    from ghidra.program.model.listing import CodeUnit

    monitor = ConsoleTaskMonitor()
    fm = program.getFunctionManager()
    listing = program.getListing()
    mem = program.getMemory()
    addr_factory = program.getAddressFactory()
    default_space = addr_factory.getDefaultAddressSpace()
    base_va = program.getImageBase().getOffset()  # keep signed form for getAddress() calls
    base_low32 = 0xdc350000

    offset = TARGET_VA_LOW32 - base_low32
    target_va = default_space.getAddress(base_va + offset)
    print(f"Target VA: {target_va}")

    tx_id = program.startTransaction("analyze g_part_gpt")
    try:
        prologue = find_prologue(mem, target_va)
        print(f"Prologue found at: {prologue}")
        entry = prologue if prologue is not None else target_va

        f = fm.getFunctionAt(entry)
        if f is None:
            if listing.getInstructionAt(entry) is None:
                dcmd = DisassembleCommand(entry, AddressSet(entry, entry.add(8192)), False)
                dcmd.applyTo(program, monitor)
            cmd = CreateFunctionCmd(entry)
            if cmd.applyTo(program, monitor):
                f = fm.getFunctionAt(entry)
            else:
                print("CreateFunctionCmd failed:", cmd.getStatusMsg())
    finally:
        program.endTransaction(tx_id, True)

    if f is None:
        print("Could not create/find function, aborting")
        return

    print(f"Function: {f.getName()} at {f.getEntryPoint()}, body size {f.getBody().getNumAddresses()}")

    # --- Dump raw disassembly with branch/jump info, in a window around target ---
    print("\n" + "=" * 70)
    print("DISASSEMBLY WINDOW around target (with branch targets)")
    print("=" * 70)
    win_start = target_va.subtract(0x200)
    win_end = target_va.add(0x100)
    instr = listing.getInstructionAt(win_start)
    if instr is None:
        instr = listing.getInstructionContaining(win_start)
    addr = win_start
    count = 0
    ins = listing.getInstructionAt(addr)
    # walk from function entry printing all instructions up to win_end, marking target
    cur = listing.getInstructionAt(f.getEntryPoint())
    while cur is not None and cur.getAddress().compareTo(win_end) <= 0 and count < 4000:
        a = cur.getAddress()
        marker = "  <<<< TARGET" if a.equals(target_va) else ""
        flow = cur.getFlowType()
        extra = ""
        if flow.isJump() or flow.isConditional() or flow.isCall():
            try:
                flows = cur.getFlows()
                tgts = ", ".join(str(t) for t in flows)
                extra = f"   [flow={flow} -> {tgts}]"
            except Exception:
                extra = f"   [flow={flow}]"
        if a.compareTo(win_start) >= 0:
            print(f"{a}: {cur}{extra}{marker}")
            count += 1
        cur = cur.getNext()

    # --- Decompile (resolves if/else from CFG automatically) ---
    print("\n" + "=" * 70)
    print("DECOMPILED C (resolves conditionals from CFG)")
    print("=" * 70)
    decomp = DecompInterface()
    opts = DecompileOptions()
    opts.setDefaultTimeout(180)
    decomp.setOptions(opts)
    decomp.openProgram(program)
    res = decomp.decompileFunction(f, 180, monitor)
    if res and res.decompileCompleted():
        src = res.getDecompiledFunction().getC()
        out_file = os.path.join(OUT_DIR, f"decompiled_{TARGET_VA_LOW32:08x}_gpartgpt_full.c")
        with open(out_file, "w") as fh:
            fh.write(f"// Full-context decompile of function containing 0x{TARGET_VA_LOW32:08x}\n")
            fh.write(f"// Function entry: {f.getEntryPoint()} name: {f.getName()}\n\n")
            fh.write(src)
        print(src)
        print(f"\nSaved to {out_file}")
    else:
        print("Decompile failed")
    decomp.dispose()


if __name__ == "__main__":
    main()
