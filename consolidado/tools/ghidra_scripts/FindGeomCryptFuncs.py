# Ghidra headless script: Find functions referencing GEOM_CRYPT strings
# Uso:
#   analyzeHeadless <project_loc> <project> -import /mnt/t/downloads/PS4/linux_project/consolidado/memoriateste.bin \
#       -postScript FindGeomCryptFuncs.py \
#       -scriptPath /mnt/t/downloads/PS4/linux_project/consolidado/tools/ghidra_scripts \
#       -readOnly

from ghidra.app.decompiler import DecompInterface
from ghidra.util.task import ConsoleTaskMonitor
from ghidra.program.model.address import AddressSet
from ghidra.program.model.listing import CodeUnit

TARGET_STRINGS = [
    "eap key setup",
    "applying eap key",
    "applying XTS",
    "applying main key",
    "applying main key 2",
    "applying ext key",
]

OUT_DIR = "/mnt/t/downloads/PS4/linux_project/consolidado/decompiled/geom_crypt"

def main():
    import os
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)

    program = currentProgram
    listing = program.getListing()
    mem = program.getMemory()
    
    decomp = DecompInterface()
    decomp.openProgram(program)
    monitor = ConsoleTaskMonitor()

    print("=" * 60)
    print("Finding GEOM_CRYPT string references...")
    print("=" * 60)

    found_funcs = set()
    
    # Search for strings in memory
    for block in mem.getBlocks():
        if not block.isRead():
            continue
        data = bytearray(block.getSize())
        mem.getBytes(block.getStart(), data)
        data_str = data.decode('ascii', errors='ignore')
        
        for target in TARGET_STRINGS:
            idx = 0
            while True:
                idx = data_str.find(target, idx)
                if idx == -1:
                    break
                str_addr = block.getStart().add(idx)
                print(f"[FOUND] String '{target}' at {str_addr}")
                
                # Find references TO this address
                refs = listing.getReferencesTo(str_addr)
                for ref in refs:
                    ref_addr = ref.getFromAddress()
                    func = listing.getFunctionContaining(ref_addr)
                    if func:
                        found_funcs.add(func)
                        print(f"  -> Referenced from {ref_addr} in function {func.getName()} ({func.getEntryPoint()})")
                idx += 1

    print(f"\nTotal unique functions found: {len(found_funcs)}")
    
    # Decompile each function
    for func in sorted(found_funcs, key=lambda f: f.getEntryPoint().getOffset()):
        addr = func.getEntryPoint().getOffset()
        name = func.getName()
        short = "%08x" % (addr & 0xffffffff)
        out_file = os.path.join(OUT_DIR, f"decompiled_{short}_{name}.c")
        
        try:
            res = decomp.decompileFunction(func, 120, monitor)
            if res and res.decompileCompleted():
                src = res.getDecompiledFunction().getC()
                with open(out_file, "w") as f:
                    f.write(f"// addr: 0x{addr:016x}  name: {name}\n")
                    f.write(f"// size: {func.getBody().getNumAddresses()}\n")
                    f.write(f"// callers: {len(list(func.getCallingFunctions()))}  calls: {len(list(func.getCalledFunctions()))}\n\n")
                    f.write(src)
                print(f"[OK] 0x{addr:016x} {name} -> {os.path.basename(out_file)}")
            else:
                print(f"[FAIL] 0x{addr:016x} {name} - decompilation incomplete")
        except Exception as e:
            print(f"[EXC] 0x{addr:016x} {name} - {e}")

    decomp.disposeProgram(program)
    print("=" * 60)
    print("DONE")

main()
