#!/usr/bin/env python3
"""
Extrai decompilação C das lacunas MTS/GBE/ICC/glue do projeto Ghidra orbis_mts
previamente analisado (consolidado/tools/ghidra_project/orbis_mts).

Executa FORA do Ghidra - usa PyGhidra como biblioteca Python pura.
Requer: pyghidra instalado no Python virtualenv (/tmp/opencode/ghidra_venv).

Uso:
    /tmp/opencode/ghidra_venv/bin/python consolidate_decompiled_lacunas.py
"""

import os
import sys

# Configura Ghidra install dir ANTES de importar pyghidra
os.environ["GHIDRA_INSTALL_DIR"] = "/mnt/hdauxiliar/ghidra_12.1.2"

import pyghidra
from pyghidra import open_project, consume_program, task_monitor

PROJECT_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/tools/ghidra_project"
PROJECT_NAME = "orbis_mts"
PROGRAM_PATH = "/kmem_dump_1252.bin"  # path dentro do projeto

OUT_DIR = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/decompiled/extracted"

# Endereços-alvo das LACUNAS de MTS/GBE/ICC/glue
TARGET_ADDRS = [
    # MTS driver (lacunas validadas em test_history)
    0xffffffffdc5a2840, 0xffffffffdc5a2950, 0xffffffffdc5a4950,
    0xffffffffdc5a4e90, 0xffffffffdc5a5050, 0xffffffffdc5a5200, 0xffffffffdc5a6290,
    # MTS helpers
    0xffffffffdc5ba8d0, 0xffffffffdc5baa30,
    # Glue/PCIe
    0xffffffffdc6dfb60, 0xffffffffdc7187a0, 0xffffffffdc7187d0, 0xffffffffdc718800,
    # ICC
    0xffffffffdc3f5bd0, 0xffffffffdc574150, 0xffffffffdc528ef0,
    # GBE
    0xffffffffdc529ed0, 0xffffffffdc529f40, 0xffffffffdc52a4f0,
]


def main():
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)

    # Inicia JVM Headless
    if not pyghidra.started():
        from pyghidra.launcher import HeadlessPyGhidraLauncher
        HeadlessPyGhidraLauncher().start()

    project = open_project(PROJECT_PATH, PROJECT_NAME, create=False)
    print(f"Projeto aberto: {project}")

    program, consumer = consume_program(project, PROGRAM_PATH)
    print(f"Programa aberto: {program.getName()}")

    fm = program.getFunctionManager()
    listing = program.getListing()
    af = program.getAddressFactory()
    mem = program.getMemory()
    monitor = task_monitor()

    from ghidra.app.decompiler import DecompInterface, DecompileOptions
    from ghidra.app.cmd.disassemble import DisassembleCommand
    from ghidra.app.cmd.function import CreateFunctionCmd
    from ghidra.program.model.address import AddressSet

    decomp = DecompInterface()
    # Timeout default de 60s por função pode ser ajustado via DecompInterface.setSimplificationStyle
    # mas por enquanto usamos o padrao.
    decomp.openProgram(program)

    extracted = skipped = failed = created = not_in_mem = 0

    print("=" * 70)
    print(f"ExtractMtsNamespacePyGhidra: {len(TARGET_ADDRS)} enderecos alvo")
    print("=" * 70)

    for addr_int in TARGET_ADDRS:
        # JPype: Java long é signed 64-bit. Endereços 0xffffffffdc5a0070 precisam
        # ser representados como signed (negativo) pois Java long é signed.
        if addr_int >= 0x8000000000000000:
            addr_long = addr_int - (1 << 64)
        else:
            addr_long = addr_int
        addr = af.getDefaultAddressSpace().getAddress(addr_long)

        if not mem.contains(addr):
            not_in_mem += 1
            print(f"[NOT-IN-MEM] 0x{addr_int:016x}")
            continue

        short = f"{addr_int:016x}"[-8:]
        out_file = os.path.join(OUT_DIR, f"decompiled_{short}.txt")
        if os.path.exists(out_file):
            skipped += 1
            print(f"[SKIP-EXIST] 0x{addr_int:016x}")
            continue

        f = fm.getFunctionAt(addr)
        if f is None:
            # Forçar disassembly + criar função
            end_addr = af.getDefaultAddressSpace().getAddress(addr_long + 255)
            disasm_set = AddressSet(addr, end_addr)
            disasm = DisassembleCommand(disasm_set, False)
            disasm.enableCodeAnalysis(False)
            disasm.applyTo(program, monitor)
            cmd = CreateFunctionCmd(addr)
            try:
                if cmd.applyTo(program, monitor):
                    created += 1
                    f = fm.getFunctionAt(addr)
                else:
                    failed += 1
                    print(f"[CREATE-FAIL] 0x{addr_int:016x} {cmd.getStatusMsg()}")
                    continue
            except Exception as e:
                failed += 1
                print(f"[CREATE-EXC] 0x{addr_int:016x} {e}")
                continue

        if f is None:
            failed += 1
            print(f"[NO-FUNC] 0x{addr_int:016x}")
            continue

        try:
            res = decomp.decompileFunction(f, 90, monitor)
            if res is not None and res.decompileCompleted():
                src = res.getDecompiledFunction().getC()
                callers = list(f.getCallingFunctions(monitor))
                callees = list(f.getCalledFunctions(monitor))
                with open(out_file, "w") as fh:
                    fh.write(f"// Extraido por Ghidra PyGhidra (consolidate_decompiled_lacunas.py)\n")
                    fh.write(f"// addr: 0x{addr_int:016x}  name: {f.getName()}  size: {f.getBody().getNumAddresses()}\n")
                    fh.write(f"// escopo: lacuna MTS/GBE/ICC/glue identificada em testes ao vivo\n")
                    fh.write(f"// chamadores ({len(callers)}):\n")
                    for c in callers[:20]:
                        fh.write(f"//   {c.getName()} @ 0x{c.getEntryPoint().getOffset():016x}\n")
                    if len(callers) > 20:
                        fh.write(f"//   ... +{len(callers) - 20} mais\n")
                    fh.write(f"// chamadas ({len(callees)}):\n")
                    for c in callees[:20]:
                        fh.write(f"//   {c.getName()} @ 0x{c.getEntryPoint().getOffset():016x}\n")
                    if len(callees) > 20:
                        fh.write(f"//   ... +{len(callees) - 20} mais\n")
                    fh.write("\n")
                    fh.write(src)
                extracted += 1
                print(f"[OK] 0x{addr_int:016x} -> {os.path.basename(out_file)}  callers={len(callers)} callees={len(callees)}")
            else:
                failed += 1
                print(f"[DECOMP-FAIL] 0x{addr_int:016x}")
        except Exception as e:
            failed += 1
            print(f"[EXC] 0x{addr_int:016x} {e}")

    decomp.closeProgram()
    program.release(consumer)
    project.close()

    summary = os.path.join(OUT_DIR, "_extraction_summary.txt")
    with open(summary, "w") as s:
        s.write("Resumo consolidate_decompiled_lacunas.py (PyGhidra)\n")
        s.write("=" * 60 + "\n")
        s.write(f"Enderecos-alvo:           {len(TARGET_ADDRS)}\n")
        s.write(f"Extraidos agora:          {extracted}\n")
        s.write(f"Skipped (ja existiam):    {skipped}\n")
        s.write(f"Falhas:                   {failed}\n")
        s.write(f"Fora da mem do program:   {not_in_mem}\n")
        s.write(f"Funcoes criadas:          {created}\n")
    print("=" * 70)
    print(f"FINAL: extracted={extracted} skipped={skipped} failed={failed} created={created} notInMem={not_in_mem}")
    print(f"Summary: {summary}")


if __name__ == "__main__":
    main()
