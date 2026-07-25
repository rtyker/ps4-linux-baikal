# PyGhidra script (CPython 3.x com JPype bridge)
# Extrai decompilação C das lacunas MTS/GBE/ICC/glue.
# Uso:
#   /tmp/opencode/ghidra_venv/bin/pyghidra \
#     --install-dir /mnt/hdauxiliar/ghidra_12.1.2 \
#     --skip-analysis \
#     <binary_path> <this_script_path>

#@category PS4-MTS

import os
import sys
from ghidra.app.decompiler import DecompInterface, DecompileOptions
from ghidra.app.cmd.disassemble import DisassembleCommand
from ghidra.app.cmd.function import CreateFunctionCmd

OUT_DIR = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/decompiled/extracted"

TARGET_ADDRS = [
    # MTS driver
    0xffffffffdc5a2840, 0xffffffffdc5a2950, 0xffffffffdc5a4950,
    0xffffffffdc5a4e90, 0xffffffffdc5a5050, 0xffffffffdc5a5200, 0xffffffffdc5a6290,
    # MTS helpers
    0xffffffffdc5ba8d0, 0xffffffffdc5baa30,
    # Glue
    0xffffffffdc6dfb60, 0xffffffffdc7187a0, 0xffffffffdc7187d0, 0xffffffffdc718800,
    # ICC
    0xffffffffdc3f5bd0, 0xffffffffdc574150, 0xffffffffdc528ef0,
    # GBE
    0xffffffffdc529ed0, 0xffffffffdc529f40, 0xffffffffdc52a4f0,
]

def run():
    program = currentProgram
    fm = program.getFunctionManager()
    listing = program.getListing()
    af = program.getAddressFactory()
    monitor = getMonitor()

    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)

    # Decompiler setup
    decomp = DecompInterface()
    opts = DecompileOptions()
    opts.setDecompilerMaxTimeout(60)
    decomp.setOptions(opts)
    decomp.openProgram(program)

    extracted = skipped = failed = created = not_in_mem = 0

    print("=" * 70)
    print("ExtractMtsNamespace (PyGhidra): %d enderecos alvo" % len(TARGET_ADDRS))
    print("=" * 70)

    for addr_int in TARGET_ADDRS:
        addr = af.getDefaultAddressSpace().getAddress(addr_int)

        if not program.getMemory().contains(addr):
            not_in_mem += 1
            print("[NOT-IN-MEM] 0x%016x" % addr_int)
            continue

        short = "%016x" % addr_int
        short = short[-8:]
        out_file = os.path.join(OUT_DIR, "decompiled_%s.txt" % short)
        if os.path.exists(out_file):
            skipped += 1
            print("[SKIP] 0x%016x already extracted" % addr_int)
            continue

        f = fm.getFunctionAt(addr)
        if f is None:
            # force disassemble + create function
            end_addr = af.getDefaultAddressSpace().getAddress(addr_int + 255)
            from ghidra.program.model.address import AddressSet
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
                    print("[CREATE-FAIL] 0x%016x %s" % (addr_int, cmd.getStatusMsg()))
                    continue
            except Exception as e:
                failed += 1
                print("[CREATE-EXC] 0x%016x %s" % (addr_int, str(e)))
                continue

        if f is None:
            failed += 1
            print("[NO-FUNC] 0x%016x" % addr_int)
            continue

        try:
            res = decomp.decompileFunction(f, 90, monitor)
            if res is not None and res.decompileCompleted():
                src = res.getDecompiledFunction().getC()
                callers = list(f.getCallingFunctions())
                callees = list(f.getCalledFunctions())
                with open(out_file, "w") as fh:
                    fh.write("// Extraido por Ghidra PyGhidra headless\n")
                    fh.write("// addr: 0x%016x  name: %s  size: %d\n" % (
                        addr_int, f.getName(), f.getBody().getNumAddresses()))
                    fh.write("// escopo: lacuna MTS/GBE/ICC/glue\n")
                    fh.write("// chamadores (%d):\n" % len(callers))
                    for c in callers[:20]:
                        fh.write("//   %s @ 0x%016x\n" % (c.getName(), c.getEntryPoint().getOffset()))
                    if len(callers) > 20:
                        fh.write("//   ... +%d mais\n" % (len(callers) - 20))
                    fh.write("// chamadas (%d):\n" % len(callees))
                    for c in callees[:20]:
                        fh.write("//   %s @ 0x%016x\n" % (c.getName(), c.getEntryPoint().getOffset()))
                    if len(callees) > 20:
                        fh.write("//   ... +%d mais\n" % (len(callees) - 20))
                    fh.write("\n")
                    fh.write(src)
                extracted += 1
                print("[OK] 0x%016x -> %s  callers=%d callees=%d" % (
                    addr_int, os.path.basename(out_file), len(callers), len(callees)))
            else:
                failed += 1
                print("[DECOMP-FAIL] 0x%016x" % addr_int)
        except Exception as e:
            failed += 1
            print("[EXC] 0x%016x %s" % (addr_int, str(e)))

    decomp.disposeProgram(program)

    summary = os.path.join(OUT_DIR, "_extraction_summary.txt")
    with open(summary, "w") as s:
        s.write("Resumo ExtractMtsNamespace (PyGhidra)\n")
        s.write("=" * 50 + "\n")
        s.write("Enderecos-alvo:           %d\n" % len(TARGET_ADDRS))
        s.write("Extraidos agora:          %d\n" % extracted)
        s.write("Skipped (ja existiam):    %d\n" % skipped)
        s.write("Falhas:                   %d\n" % failed)
        s.write("Fora da mem do program:   %d\n" % not_in_mem)
        s.write("Funcoes criadas:          %d\n" % created)
    print("=" * 70)
    print("FINAL: extracted=%d skipped=%d failed=%d created=%d notInMem=%d" % (
        extracted, skipped, failed, created, not_in_mem))
    print("Summary: %s" % summary)

run()
