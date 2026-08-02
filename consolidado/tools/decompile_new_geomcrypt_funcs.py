#!/usr/bin/env python3
"""Decompila os 3 ponteiros de funcao novos achados na struct g_class de
GEOM_CRYPT (dc9a20e0, dc9a3050, dc9a31b0), alem de gravar a struct g_class
inteira (12 classes GEOM) como referencia."""
import os
os.environ["GHIDRA_INSTALL_DIR"] = "/ghidra"
import pyghidra
from pyghidra import open_project, consume_program

PROJECT_PATH = "/workspace/consolidado/tools/ghidra_project"
PROJECT_NAME = "orbis_mts"
PROGRAM_PATH = "/kmem_dump_1252.bin"
OUT_DIR = "/workspace/consolidado/decompiled/geom_crypt"

TARGETS = [0xdc9a20e0, 0xdc9a3050, 0xdc9a31b0]


def find_prologue(mem, start_va):
    start_off = start_va.getOffset()
    space = start_va.getAddressSpace()
    for back in range(0, 4096):
        try:
            cand = space.getAddress(start_off - back)
            b0 = mem.getByte(cand) & 0xff
            if b0 == 0x55:
                if (mem.getByte(cand.add(1)) & 0xff) == 0x48 and (mem.getByte(cand.add(2)) & 0xff) == 0x89 and (mem.getByte(cand.add(3)) & 0xff) == 0xe5:
                    return cand
            elif b0 == 0xf3:
                if (mem.getByte(cand.add(1)) & 0xff) == 0x0f and (mem.getByte(cand.add(2)) & 0xff) == 0x1e and (mem.getByte(cand.add(3)) & 0xff) == 0xfa:
                    return cand
        except Exception:
            pass
    return None


def main():
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
    mem = program.getMemory()
    addr_factory = program.getAddressFactory()
    default_space = addr_factory.getDefaultAddressSpace()
    base_va = program.getImageBase().getOffset()  # signed form
    base_low32 = 0xdc350000

    decomp = DecompInterface()
    opts = DecompileOptions()
    opts.setDefaultTimeout(120)
    decomp.setOptions(opts)
    decomp.openProgram(program)

    for t in TARGETS:
        offset = t - base_low32
        va = default_space.getAddress(base_va + offset)
        tx = program.startTransaction(f"seed {t:x}")
        try:
            prologue = find_prologue(mem, va)
            entry = prologue if prologue else va
            f = fm.getFunctionAt(entry)
            if f is None:
                if listing.getInstructionAt(entry) is None:
                    DisassembleCommand(entry, AddressSet(entry, entry.add(4096)), False).applyTo(program, monitor)
                cmd = CreateFunctionCmd(entry)
                if cmd.applyTo(program, monitor):
                    f = fm.getFunctionAt(entry)
        finally:
            program.endTransaction(tx, True)

        if f is None:
            print(f"0x{t:x}: FAILED to create function")
            continue

        res = decomp.decompileFunction(f, 120, monitor)
        if res and res.decompileCompleted():
            src = res.getDecompiledFunction().getC()
            out_file = os.path.join(OUT_DIR, f"decompiled_{t:08x}_geomcrypt_classfunc.c")
            with open(out_file, "w") as fh:
                fh.write(f"// GEOM_CRYPT struct g_class extra function pointer\n")
                fh.write(f"// addr: 0x{t:08x}  entry: {f.getEntryPoint()}  name: {f.getName()}\n\n")
                fh.write(src)
            print(f"0x{t:x}: OK -> {out_file}")
            print(src[:800])
            print("...\n")
        else:
            print(f"0x{t:x}: decompile FAILED")

    decomp.dispose()


if __name__ == "__main__":
    main()
