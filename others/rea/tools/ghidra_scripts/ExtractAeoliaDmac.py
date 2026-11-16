# Ghidra headless script: extrai funções do Aeolia DMAC (00:14.7)
# Foco: aeolia_dmac_xfer_upstream, PCI match, device handlers, registradores DMAC
#
# Uso:
#   analyzeHeadless <project_loc> <project> \
#       -import kmem_dump_1252.bin -noanalysis -overwrite \
#       -postScript ExtractAeoliaDmac.py \
#       -scriptPath /mnt/hdauxiliar/ps4-linux-baikal/others/rea/tools/ghidra_scripts

#@category PS4-AeoliaDMAC
#@author opencode-automation

import os
import re
from ghidra.app.decompiler import DecompInterface, DecompileOptions
from ghidra.util.task import ConsoleTaskMonitor
from ghidra.program.model.address import AddressSet
from ghidra.app.cmd.function import CreateFunctionCmd
from ghidra.program.model.symbol import SourceType
from ghidra.app.cmd.disassemble import DisassembleCommand

# Diretórios de saída
_KERNEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT_DIR = _KERNEL + "/rea/decompiled/aeolia_dmac"
EXISTING_DIRS = [
    _KERNEL + "/rea/decompiled",
    _KERNEL + "/rea/decompiled/legacy_raiz",
    _KERNEL + "/rea/decompiled/extracted",
]

# Endereços-alvo do Aeolia DMAC (calculados a partir do dump)
TARGET_ADDRS = [
    # ===== PCI Device Match Function =====
    0xffffffffdc7c1090,  # PCI match function (início) - itera tabela de devices
    0xffffffffdc7c11c0,  # Check vendor 0x104d
    0xffffffffdc7c11c5,  # Check device 0x90dd (SPM)
    0xffffffffdc7c11d5,  # Check device 0x90ce (Aeolia DMA1?)
    0xffffffffdc7c11e5,  # Check device 0x90a3 (Aeolia DMA2?)
    0xffffffffdc7c11fd,  # SPM handler target (je +0x30)
    0xffffffffdc7c1223,  # Device 0x90ce handler target (je +0x48)
    0xffffffffdc7c11e7,  # Device 0x90a3 handler (fallthrough)

    # ===== aeolia_dmac_xfer_upstream =====
    0xffffffffdce32e00,  # Área da string "aeolia_dmac_xfer_upstream" - buscar função chamadora
    0xffffffffdce32ea9,  # Endereço exato da string

    # ===== Strings de device Aeolia (para achar referências no código) =====
    0xffffffffdcaf7373,  # "aeolia_dmac_pci"
    0xffffffffdcaf7383,  # "pci/aeolia_dmac"
    0xffffffffdcaf7393,  # "pci/dmac"
    0xffffffffdcaf73a3,  # "Aeolia DMA1 controller"
    0xffffffffdcaf73b3,  # "Aeolia DMA2 controller"

    # ===== DDR3 Swap strings (para achar thread e chamadas de DMA) =====
    0xffffffffdcb3a964,  # "SceDdr3Swap"
    0xffffffffdcb3a8d2,  # "ddr3swap_state"
    0xffffffffdcb3a910,  # "init_swap"
    0xffffffffdcb3a930,  # "prepare_swap"
    0xffffffffdcb3a950,  # "ddr3swap:mtx"
    0xffffffffdcb3a9f0,  # "ddr3swap_crypt:mtx"

    # ===== bd_sched_hdd_writer_write_hdd (chama aeolia_dmac_xfer_upstream) =====
    0xffffffffdce32e8c,  # Início da função (baseado em "bd_sched_hdd_writer_write_hdd" string)
]

ADDR_RE = re.compile(r"0xffffffff(dc[0-9a-f]{5})")

def short_name(addr):
    s = "%016x" % (addr & 0xffffffffffffffff)
    return s[-8:]

def scan_existing():
    existing = set()
    for d in EXISTING_DIRS:
        if not os.path.isdir(d):
            continue
        for fn in os.listdir(d):
            if not fn.endswith(".txt"):
                continue
            path = os.path.join(d, fn)
            try:
                with open(path, "r") as f:
                    head = f.read(2048)
                m = ADDR_RE.search(head)
                if m:
                    existing.add(int(m.group(1), 16))
            except Exception:
                pass
    return existing

def main():
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)
    existing = scan_existing()

    program = currentProgram
    fm = program.getFunctionManager()
    listing = program.getListing()
    monitor = ConsoleTaskMonitor()

    # Disassemble ranges alvo
    addrFactory = program.getAddressFactory()
    addrSpace = addrFactory.getDefaultAddressSpace()

    disasm_needed = AddressSet()
    for addr_int in TARGET_ADDRS:
        addr = addrSpace.getAddress(addr_int)
        if listing.getInstructionAt(addr) is None:
            end_addr = addrSpace.getAddress(addr_int + 511)  # 512 bytes
            disasm_needed.add(addr, end_addr)
    if not disasm_needed.isEmpty():
        print("Disassembling %d ranges alvo..." % disasm_needed.getNumAddressRanges())
        for rng in disasm_needed:
            sub_set = AddressSet(rng.getMinAddress(), rng.getMaxAddress())
            cmd = DisassembleCommand(sub_set, False)
            cmd.enableCodeAnalysis(False)
            try:
                cmd.applyTo(program, monitor)
            except Exception as e:
                print("disasm fail @ %s: %s" % (rng.getMinAddress(), str(e)))

    # Decompiler
    decomp = DecompInterface()
    decomp_options = DecompileOptions()
    decomp_options.setDecompilerMaxTimeout(120)
    decomp.setOptions(decomp_options)
    decomp.openProgram(program)

    extracted = 0
    skipped = 0
    failed = 0
    created = 0
    not_in_memory = 0

    print("=" * 70)
    print("ExtractAeoliaDmac: %d enderecos alvo" % len(TARGET_ADDRS))
    print("=" * 70)

    for addr_int in TARGET_ADDRS:
        addr = program.getAddressFactory().getDefaultAddressSpace().getAddress(addr_int)
        if not listing.containsAt(addr):
            not_in_memory += 1
            print("[NOT-IN-MEM] 0x%016x" % addr_int)
            continue

        short = short_name(addr_int)
        low20 = addr_int & 0xfffff
        if low20 in existing or (addr_int & 0xffffff) in existing or (addr_int & 0xffff) in existing:
            skipped += 1
            print("[SKIP-EXIST] 0x%016x %s" % (addr_int, short))
            continue

        out_file = os.path.join(OUT_DIR, "decompiled_%s.txt" % short)
        if os.path.exists(out_file):
            skipped += 1
            continue

        f = fm.getFunctionAt(addr)
        if f is None:
            cmd = CreateFunctionCmd(addr)
            try:
                cmd.applyTo(program, monitor)
                if cmd.getStatus():
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
            res = decomp.decompileFunction(f, 120, monitor)
            if res and res.decompileCompleted():
                src = res.getDecompiledFunction().getC()
                callers = list(f.getCallingFunctions())
                callees = list(f.getCalledFunctions())
                with open(out_file, "w") as fh:
                    fh.write("// Extraido por Ghidra headless (ExtractAeoliaDmac.py)\n")
                    fh.write("// addr: 0x%016x  name: %s  size: %d\n" % (
                        addr_int, f.getName(), f.getBody().getNumAddresses()))
                    fh.write("// escopo: Aeolia DMAC (00:14.7) - DDR3 swap engine\n")
                    fh.write("// chamadores (%d):\n" % len(callers))
                    for c in callers[:30]:
                        fh.write("//   %s @ 0x%016x\n" % (c.getName(), c.getEntryPoint().getOffset()))
                    if len(callers) > 30:
                        fh.write("//   ... +%d mais\n" % (len(callers) - 30))
                    fh.write("// chamadas (%d):\n" % len(callees))
                    for c in callees[:30]:
                        fh.write("//   %s @ 0x%016x\n" % (c.getName(), c.getEntryPoint().getOffset()))
                    if len(callees) > 30:
                        fh.write("//   ... +%d mais\n" % (len(callees) - 30))
                    fh.write("\n")
                    fh.write(src.encode('ascii', 'replace').decode('ascii'))
                extracted += 1
                print("[OK] 0x%016x -> %s  (created=%s, callers=%d, callees=%d)" % (
                    addr_int, os.path.basename(out_file), created > 0, len(callers), len(callees)))
            else:
                failed += 1
                print("[DECOMP-FAIL] 0x%016x" % addr_int)
        except Exception as e:
            failed += 1
            print("[EXC] 0x%016x %s" % (addr_int, str(e)))

    decomp.disposeProgram(program)

    # Summary
    summary = os.path.join(OUT_DIR, "_extraction_summary.txt")
    with open(summary, "w") as s:
        s.write("Resumo ExtractAeoliaDmac.py\n")
        s.write("=" * 50 + "\n")
        s.write("Enderecos-alvo:           %d\n" % len(TARGET_ADDRS))
        s.write("Extraidos agora:          %d\n" % extracted)
        s.write("Skipped (ja existiam):    %d\n" % skipped)
        s.write("Falhas (decomp):          %d\n" % failed)
        s.write("Fora da MEM do program:   %d\n" % not_in_memory)
        s.write("Funcoes criadas:          %d\n" % created)
    print("=" * 70)
    print("FINAL: extracted=%d  skipped=%d  failed=%d  created=%d  notInMem=%d" % (
        extracted, skipped, failed, created, not_in_memory))
    print("Summary: %s" % summary)

main()