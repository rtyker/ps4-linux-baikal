# Ghidra script: Trace IV offset and provider structure fields for GEOM_CRYPT and g_part
#
# Usage:
#   analyzeHeadless <project_loc> <project> \
#       -process kmem_dump_1252.bin -noanalysis \
#       -postScript TraceIvOffsetFormula.py \
#       -scriptPath /mnt/t/downloads/PS4/linux_project/consolidado/tools/ghidra_scripts \
#       -readOnly

from ghidra.app.decompiler import DecompInterface, DecompileOptions
from ghidra.util.task import ConsoleTaskMonitor

print("=== TraceIvOffsetFormula.py starting ===")

options = DecompileOptions()
decomp = DecompInterface()
decomp.setOptions(options)
decomp.openProgram(currentProgram)

fm = currentProgram.getFunctionManager()
addr_factory = currentProgram.getAddressFactory().getDefaultAddressSpace()

def get_func_at(va_hex):
    addr = addr_factory.getAddress(va_hex)
    f = fm.getFunctionAt(addr)
    if f is None:
        # Try to find function containing address
        f = fm.getFunctionContaining(addr)
    return f

# Targets of interest:
# 1. 0xffffffffdc9a40d0 (g_crypt_create_provider)
# 2. 0xffffffffdc9a1ce0 (g_crypt_taste)
# 3. 0xffffffffdc8dabae (g_part_gpt)
# 4. 0xffffffffdc8dab50 (g_part_gpt_create_provider)

target_addrs = [0xffffffffdc9a40d0, 0xffffffffdc9a1ce0, 0xffffffffdc8dabae, 0xffffffffdc8dab50]

for va in target_addrs:
    f = get_func_at(va)
    if f:
        print("Found function %s at 0x%x" % (f.getName(), va))
        res = decomp.decompileFunction(f, 30, ConsoleTaskMonitor())
        if res and res.decompiledFunction:
            ccode = res.decompiledFunction.getC()
            print("--- C Code for 0x%x (%s) ---" % (va, f.getName()))
            lines = ccode.splitlines()
            for idx, line in enumerate(lines[:120]):
                print("%3d: %s" % (idx + 1, line))
            print("--- End C Code ---")
        else:
            print("Failed to decompile 0x%x" % va)
    else:
        print("No function found at 0x%x" % va)

print("=== TraceIvOffsetFormula.py finished ===")
