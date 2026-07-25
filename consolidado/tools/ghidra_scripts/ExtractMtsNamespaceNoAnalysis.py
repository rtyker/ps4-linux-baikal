# Ghidra headless script: cria funções no namespace MTS/GBE/ICC/glue
# e decompila cada uma. Feito para rodar SEM analysis default do Ghidra
# (que demora 15+ min em dumps de 33MB por causa do DecompilerParameterId).
#
# Uso:
#   analyzeHeadless <project_loc> <project> \
#       -import kmem_dump_1252.bin -noanalysis -overwrite \
#       -postScript ExtractMtsNamespaceNoAnalysis.py \
#       -scriptPath /mnt/t/downloads/PS4/linux_in_ps4/consolidado/tools/ghidra_scripts

#@category PS4-MTS
#@author opencode-automation

import os
import re
from ghidra.app.decompiler import DecompInterface, DecompileOptions
from ghidra.util.task import ConsoleTaskMonitor
from ghidra.program.model.address import AddressSet
from ghidra.app.cmd.function import CreateFunctionCmd
from ghidra.program.model.symbol import SourceType

OUT_DIR = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/decompiled/extracted"
EXISTING_DIRS = [
    "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/decompiled",
    "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/decompiled/legacy_raiz",
]

# Endereços-base conhecidos das lacunas MTS (validados em testes ao vivo)
# e da arvore direta do driver. Cada endereço = início de uma função
# (prólogo x86-64 com push rbp / mov rbp,rsp).
TARGET_ADDRS = [
    # ===== MTS driver - lacunas validadas em test_history =====
    0xffffffffdc5a2840,  # MDIO read high word (bits 31:16)
    0xffffffffdc5a2950,  # MDIO write opcode 0x2000
    0xffffffffdc5a4950,  # trigger BAR0+0x1c = 0x80000000 (ativou motor MAC/PHY)
    0xffffffffdc5a4e90,  # relacionado ao RMU/dc5a5200
    0xffffffffdc5a5050,  # provavel próximo do trigger
    0xffffffffdc5a5200,  # RMU sub-header 0x9807
    0xffffffffdc5a6290,  # sub-rotina vista em chamada

    # ===== MTS helpers (dc5bxxxx) =====
    0xffffffffdc5ba8d0,  # chamado por dc718eb0 (aloca BARs)
    0xffffffffdc5baa30,  # chamado por dc5a0070 (cria ifnet)

    # ===== Glue/PCIe sub-funções =====
    0xffffffffdc6dfb60,  # primitiva reset glue (chamado por dc6df850(0x4000))
    0xffffffffdc7187a0,  # glue read (chamado em dc72bfb0)
    0xffffffffdc7187d0,  # glue read (chamado em dc6df850)
    0xffffffffdc718800,  # glue write (chamado em dc6df850)

    # ===== ICC =====
    0xffffffffdc3f5bd0,  # wrapper icc_query(4, 0x38) - FUNDAMENTAL
    0xffffffffdc574150,  # registra handlers ICC (chama 6x em dc528760)
    0xffffffffdc528ef0,  # handler 4/0x38 = GBE power-on

    # ===== GBE clk/phy =====
    0xffffffffdc529ed0,  # lacuna GBE
    0xffffffffdc529f40,  # lacuna GBE
    0xffffffffdc52a4f0,  # lacuna GBE

    # ===== MTS - funções já decompiladas cuja versão bruta Ghidra ajuda a validar =====
    # (Não extrairemos essas — já existem. Apenas para conferência futura.)
]

ADDR_RE = re.compile(r"0xffffffff(dc5[0-9a-f]{4}|dc7c8[0-9a-f]{3}|dc478[0-9a-f]{3}|dc3f5[0-9a-f]{3}|dc6df[0-9a-f]{3}|dc718[0-9a-f]{3}|dc719[0-9a-f]{3})")

def short_name(addr):
    s = "%016x" % (addr & 0xffffffffffffffff)
    return s[-8:]

def scan_existing():
    """Pega endereços já decompilados para evitar reextração."""
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

    # Garantir que instruções nos endereços-alvo foram disassembladas
    # (necessario porque rodamos -noanalysis; o ElfLoader só marca code como undefined)
    from ghidra.app.cmd.disassemble import DisassembleCommand
    from ghidra.program.model.address import AddressSet
    addrFactory = program.getAddressFactory()
    addrSpace = addrFactory.getDefaultAddressSpace()

    disasm_needed = AddressSet()
    for addr_int in TARGET_ADDRS:
        addr = addrSpace.getAddress(addr_int)
        if listing.getInstructionAt(addr) is None:
            # tenta um bloco pequeno (256 bytes) para garantir
            end_addr = addrSpace.getAddress(addr_int + 255)
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

    # Decompiler options: timeout 60s por função, sem simplification crazy
    decomp = DecompInterface()
    decomp_options = DecompileOptions()
    decomp_options.setDecompilerMaxTimeout(60)
    decomp.setOptions(decomp_options)
    decomp.openProgram(program)

    extracted = 0
    skipped = 0
    failed = 0
    created = 0
    not_in_memory = 0

    print("=" * 70)
    print("ExtractMtsNamespaceNoAnalysis: %d enderecos alvo" % len(TARGET_ADDRS))
    print("=" * 70)

    for addr_int in TARGET_ADDRS:
        addr = program.getAddressFactory().getDefaultAddressSpace().getAddress(addr_int)
        # Verifica se endereço existe na memoria
        if not listing.containsAt(addr):
            # Verifica se há contém no espaço do program (pode estar nunوضع non-loaded)
            not_in_memory += 1
            print("[NOT-IN-MEM] 0x%016x" % addr_int)
            continue

        short = short_name(addr_int)
        # Pula se já decompilado nas dirs existentes
        # (compara bits baixos - tolerância)
        low20 = addr_int & 0xfffff
        if low20 in existing or (addr_int & 0xffffff) in existing or (addr_int & 0xffff) in existing:
            skipped += 1
            print("[SKIP-EXIST] 0x%016x %s" % (addr_int, short))
            continue

        out_file = os.path.join(OUT_DIR, "decompiled_%s.txt" % short)
        if os.path.exists(out_file):
            skipped += 1
            continue

        # Tenta obter função existente
        f = fm.getFunctionAt(addr)
        if f is None:
            # Tenta criar a função neste endereço
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
            res = decomp.decompileFunction(f, 90, monitor)
            if res and res.decompileCompleted():
                src = res.getDecompiledFunction().getC()
                callers = list(f.getCallingFunctions())
                callees = list(f.getCalledFunctions())
                with open(out_file, "w") as fh:
                    fh.write("// Extraido por Ghidra headless (ExtractMtsNamespaceNoAnalysis.py)\n")
                    fh.write("// addr: 0x%016x  name: %s  size: %d\n" % (
                        addr_int, f.getName(), f.getBody().getNumAddresses()))
                    fh.write("// escopo: lacuna MTS/GBE/ICC/glue identificada em testes ao vivo\n")
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
                    fh.write(src.encode('ascii', 'replace').decode('ascii'))
                extracted += 1
                print("[OK] 0x%016x -> %s  (created=%s, callers=%d, callees=%d)" % (
                    addr_int, os.path.basename(out_file), f is not None and created > 0,
                    len(callers), len(callees)))
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
        s.write("Resumo ExtractMtsNamespaceNoAnalysis.py\n")
        s.write("=" * 50 + "\n")
        s.write("Enderecos-alvo:           %d\n" % len(TARGET_ADDRS))
        s.write("Extraidos agora:          %d\n" % extracted)
        s.write("Skipped (ja existiam):    %d\n" % skipped)
        s.write("Falhas (decomp):          %d\n" % failed)
        s.write("Fora da_MEM do program:   %d\n" % not_in_memory)
        s.write("Funcoes criadas (CreateFunctionCmd): %d\n" % created)
    print("=" * 70)
    print("FINAL: extracted=%d  skipped=%d  failed=%d  created=%d  notInMem=%d" % (
        extracted, skipped, failed, created, not_in_memory))
    print("Summary: %s" % summary)

main()
