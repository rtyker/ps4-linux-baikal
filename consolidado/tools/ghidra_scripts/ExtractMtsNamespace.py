# Ghidra headless script: Extrai decompilação C de funções MTS/GBE/ICC/glue
# Uso:
#   analyzeHeadless <project_loc> <project> -process kmem_dump_1252.bin \
#       -postScript ExtractMtsNamespace.py \
#       -scriptPath /mnt/t/downloads/PS4/linux_in_ps4/consolidado/tools/ghidra_scripts \
#       -readOnly
#
# Saida: um arquivo .c por função, em consolidado/decompiled/extracted/

#@category PS4-MTS
#@author opencode-automation

import os
import re
from ghidra.app.decompiler import DecompInterface
from ghidra.util.task import ConsoleTaskMonitor

OUT_DIR = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/decompiled/extracted"
KNOWN_DIRS = [
    "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/decompiled",
    "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/decompiled/legacy_raiz",
]

# Ranges de endereços (low, high) cobrindo namespaces de interesse.
# Formato: (low64, high64) exclusive high.
TARGET_RANGES = [
    (0xffffffffdc478000, 0xffffffffdc479000),  # ICC alias
    (0xffffffffdc3f5000, 0xffffffffdc3f6000),  # icc_query wrapper
    (0xffffffffdc526000, 0xffffffffdc52b000),  # GBE clk/phy/domain
    (0xffffffffdc528000, 0xffffffffdc529000),  # icc_power dispatcher (inside dc52)
    (0xffffffffdc530000, 0xffffffffdc539000),  # GBE aux
    (0xffffffffdc536000, 0xffffffffdc538000),  # overlaps dc53 aux
    (0xffffffffdc5a0000, 0xffffffffdc5b0000),  # MTS driver completo (dc5axxxx)
    (0xffffffffdc5b0000, 0xffffffffdc5c0000),  # MTS helpers (dc5bxxxx)
    (0xffffffffdc6df000, 0xffffffffdc6e0000),  # glue block reset
    (0xffffffffdc718000, 0xffffffffdc71a000),  # glue write + baikal pcie + clock init
    (0xffffffffdc7c8000, 0xffffffffdc7c9000),  # ICC devpower
]

# Endereços-base já extraídos (preenchido por scan_known)
KNOWN_DONE = set()

ADDR_RE = re.compile(
    r"0xffffffff"
    r"(dc5[0-9a-f]{4}"
    r"|dc7c8[0-9a-f]{3}"
    r"|dc478[0-9a-f]{3}"
    r"|dc3f5[0-9a-f]{3}"
    r"|dc6df[0-9a-f]{3}"
    r"|dc718[0-9a-f]{3}"
    r"|dc719[0-9a-f]{3})"
)

def scan_known():
    """Coleta enderecos extraidos do header de cada .txt existente."""
    for d in KNOWN_DIRS:
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
                    s = m.group(1)
                    KNOWN_DONE.add(int(s, 16))
            except Exception:
                pass

def in_targets(addr):
    a = addr & 0xffffffffffffffff
    for (lo, hi) in TARGET_RANGES:
        if lo <= a < hi:
            return True
    return False

def short_name(addr):
    """dc5a0070 style."""
    s = "%016x" % (addr & 0xffffffffffffffff)
    # s = 16 hex chars. Quero os últimos 8 (dc + 6 nibbles high precisam aparecer).
    # 0xffffffffdc5a0070 -> ultimos 8: dc5a0070
    return s[-8:]

def main():
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)
    scan_known()

    program = currentProgram
    fm = program.getFunctionManager()
    monitor = ConsoleTaskMonitor()

    decomp = DecompInterface()
    decomp.openProgram(program)

    funcs = []
    func_iter = fm.getFunctions(True)
    while func_iter.hasNext():
        f = func_iter.next()
        addr = f.getEntryPoint().getOffset()
        if in_targets(addr):
            funcs.append(f)

    print("=" * 60)
    print("ExtractMtsNamespace: %d funcoes no escopo alvo" % len(funcs))
    print("=" * 60)

    extracted = 0
    skipped = 0
    failed = 0

    for f in funcs:
        addr = f.getEntryPoint().getOffset()
        sym = short_name(addr)
        # Skip se ja extraido (compara low bits 20 ou 24)
        already = False
        for d in KNOWN_DIRS + [OUT_DIR]:
            cand = os.path.join(d, "decompiled_%s.txt" % sym)
            legacy_cand = os.path.join(d, "%s.txt" % sym)
            if os.path.exists(cand) or os.path.exists(legacy_cand):
                already = True
                break
        # Também trata caso do nome ja ter prefix
        for d in KNOWN_DIRS + [OUT_DIR]:
            for suffix in ["_%s" % sym, "dc%s" % sym[2:]]:
                pass
        if already:
            skipped += 1
            continue

        out_file = os.path.join(OUT_DIR, "decompiled_%s.txt" % sym)
        try:
            res = decomp.decompileFunction(f, 120, monitor)
            if res and res.decompileCompleted():
                src = res.getDecompiledFunction().getC()
                with open(out_file, "w") as fh:
                    fh.write("// Extraido por Ghidra headless (ExtractMtsNamespace.py)\n")
                    fh.write("// addr: 0x%016x  name: %s  size: %d\n" % (
                        addr, f.getName(), f.getBody().getNumAddresses()))
                    fh.write("// escopo: namespace MTS/GBE/ICC/glue\n")
                    fh.write("// chamadores: %d  chamadas: %d\n" % (
                        len(f.getCallingFunctions()), len(f.getCalledFunctions())))
                    fh.write("\n")
                    fh.write(src.encode('ascii', 'replace'))
                extracted += 1
                print("[OK] 0x%016x -> %s" % (addr, os.path.basename(out_file)))
            else:
                failed += 1
                print("[FAIL] 0x%016x decompile incomplete" % addr)
        except Exception as e:
            failed += 1
            print("[EXC] 0x%016x %s" % (addr, str(e)))

    decomp.disposeProgram(program)

    summary = os.path.join(OUT_DIR, "_extraction_summary.txt")
    with open(summary, "w") as f:
        f.write("Resumo ExtractMtsNamespace.py\n")
        f.write("=" * 40 + "\n")
        f.write("Total no escopo:        %d\n" % len(funcs))
        f.write("Extraidas agora:        %d\n" % extracted)
        f.write("Skipped (ja existiam):  %d\n" % skipped)
        f.write("Falhas de decomp:       %d\n" % failed)
    print("=" * 60)
    print("FINAL: extracted=%d  skipped=%d  failed=%d  total=%d" % (
        extracted, skipped, failed, len(funcs)))
    print("summary: %s" % summary)

main()
