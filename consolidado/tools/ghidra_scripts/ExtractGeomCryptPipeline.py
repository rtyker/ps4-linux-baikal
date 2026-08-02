# Ghidra headless script: Find and decompile all functions in the GEOM_CRYPT
# encryption pipeline of the PS4 Orbis kernel (memoriateste.bin / kmem_dump_1252.bin).
#
# Strategy (works with -noanalysis):
#   Phase 1: Search for anchor strings directly in program memory
#   Phase 2: Disassemble surrounding code regions and scan for LEA/MOV instructions
#            referencing the string VAs (RIP-relative addressing)
#   Phase 3: Create functions at discovered call sites, walk call tree 2 levels
#   Phase 4: Decompile each function, write output to geom_crypt/
#
# Usage:
#   analyzeHeadless <project_loc> <project> \
#       -process kmem_dump_1252.bin -noanalysis \
#       -postScript ExtractGeomCryptPipeline.py \
#       -scriptPath /mnt/t/downloads/PS4/linux_project/consolidado/tools/ghidra_scripts \
#       -readOnly
#
# Or with import:
#   analyzeHeadless <project_loc> <project> \
#       -import memoriateste.bin -noanalysis -overwrite \
#       -postScript ExtractGeomCryptPipeline.py \
#       -scriptPath /mnt/t/downloads/PS4/linux_project/consolidado/tools/ghidra_scripts

#@category PS4-GEOM-CRYPT
#@author opencode-automation

import os
import struct
from ghidra.app.decompiler import DecompInterface, DecompileOptions
from ghidra.util.task import ConsoleTaskMonitor
from ghidra.app.cmd.function import CreateFunctionCmd
from ghidra.app.cmd.disassemble import DisassembleCommand
from ghidra.program.model.address import AddressSet
from ghidra.program.model.symbol import SourceType

OUT_DIR = "/mnt/t/downloads/PS4/linux_project/consolidado/decompiled/geom_crypt"

# ========================================================================
# Anchor strings to find in the binary (GEOM_CRYPT + SBL/keymgr error logs)
# ========================================================================
TARGET_STRINGS = [
    # GEOM_CRYPT pipeline strings (the core encryption chain)
    "GEOM_CRYPT[%u]: eap key setup",
    "GEOM_CRYPT[%u]: applying eap key",
    "GEOM_CRYPT[%u]: applying XTS",
    "GEOM_CRYPT[%u]: applying main key 2",
    "GEOM_CRYPT[%u]: applying ext key",
    # Note: "applying main key" is a substring of "applying main key 2"
    # so we handle it specially

    # HDD key label
    "SCE_EAP_HDD__KEY",

    # EAP sub-key labels
    "EAP_U00",
    "EAP_V00",

    # SBL/Keymgr function names (appear in error log format strings)
    "sceSblWrapHddEapPartitionKeyData",
    "sceSblGetEapInternalPartKeyAddSign",
    "sceSblAuthMgrAddEEkc ",        # trailing space to avoid matching EEkc2/3
    "sceSblAuthMgrAddEEkc2",
    "sceSblAuthMgrAddEEkc3",
    "sceSblAuthMgrDeleteEEkc",
    "sceSblKeymgrSmCallfuncWithID",
    "sceSblKeymgrLockKey",

    # Source file path
    "geom_crypt.c",
]

# Known code region for GEOM_CRYPT (from string proximity analysis)
# The strings cluster around file offsets 0xae0000-0xb20000, so functions
# referencing them should be nearby in the .text segment
GEOM_CODE_SCAN_RANGES = [
    # Range around the GEOM_CRYPT strings - likely contains the functions
    # that reference them. We'll scan this range for instructions.
    # (start_va, end_va) - we compute these from the ELF base
]

CALL_TREE_DEPTH = 2  # levels of callers+callees to follow


def short_name(addr):
    """Return last 8 hex chars of address as short name."""
    return "%08x" % (addr & 0xffffffff)


def find_strings_in_memory(program):
    """Phase 1: Find all target strings in program memory.
    Returns dict: string -> list of VAs where it was found."""
    mem = program.getMemory()
    results = {}

    print("=" * 70)
    print("Phase 1: Searching for %d anchor strings in memory..." % len(TARGET_STRINGS))
    print("=" * 70)

    for target in TARGET_STRINGS:
        target_bytes = target.encode('ascii')
        results[target] = []

        # Search all memory blocks
        for block in mem.getBlocks():
            if not block.isRead():
                continue

            block_start = block.getStart()
            block_size = block.getSize()

            # Read block data
            try:
                data = bytearray(block_size)
                mem.getBytes(block_start, data)
            except Exception:
                continue

            # Search for string
            data_bytes = bytes(data)
            idx = 0
            while True:
                idx = data_bytes.find(target_bytes, idx)
                if idx == -1:
                    break
                string_va = block_start.add(idx)
                results[target].append(string_va)
                print("  [FOUND] '%s' at VA %s" % (target, string_va))
                idx += 1

    total = sum(len(v) for v in results.values())
    found_count = sum(1 for v in results.values() if v)
    print("Phase 1 complete: %d/%d strings found, %d total occurrences" % (
        found_count, len(TARGET_STRINGS), total))
    return results


def disassemble_range(program, monitor, start_va, end_va):
    """Disassemble a range of addresses if not already disassembled."""
    listing = program.getListing()
    addr_set = AddressSet(start_va, end_va)

    # Check if already disassembled
    if listing.getInstructionAt(start_va) is not None:
        return  # already good

    cmd = DisassembleCommand(addr_set, False)
    cmd.enableCodeAnalysis(False)
    try:
        cmd.applyTo(program, monitor)
    except Exception as e:
        print("  [WARN] disassemble_range %s-%s: %s" % (start_va, end_va, e))


def scan_for_references(program, monitor, string_locations):
    """Phase 2: Scan code for instructions referencing the string VAs.
    This finds LEA/MOV instructions that load the address of each string.
    Returns dict: string -> set of (referencing_instruction_VA, containing_function_entry_VA)."""

    print("=" * 70)
    print("Phase 2: Scanning code for references to strings...")
    print("=" * 70)

    mem = program.getMemory()
    listing = program.getListing()
    addr_factory = program.getAddressFactory()
    addr_space = addr_factory.getDefaultAddressSpace()

    # Collect all unique string VAs to search for
    string_va_to_name = {}
    for name, vas in string_locations.items():
        for va in vas:
            string_va_to_name[va.getOffset()] = name

    if not string_va_to_name:
        print("  No strings found, nothing to scan.")
        return {}

    # Determine scan range from the LOAD segments
    # The .text segment is the first LOAD (R+E) - find it from memory blocks
    code_blocks = []
    for block in mem.getBlocks():
        if block.isExecute() and block.isRead():
            code_blocks.append((block.getStart(), block.getEnd()))
            print("  Executable block: %s - %s (%d bytes)" % (
                block.getStart(), block.getEnd(),
                block.getEnd().getOffset() - block.getStart().getOffset()))

    # For each string VA, we scan ALL executable blocks for RIP-relative
    # LEA instructions that compute the string's VA.
    #
    # In x86-64, LEA reg, [RIP+disp32] is encoded as:
    #   48 8D xx yy yy yy yy   (REX.W + LEA + ModRM + disp32)
    # where the effective address = instruction_addr + instruction_length + disp32
    #
    # Alternative: we scan the raw bytes of executable blocks looking for
    # 4-byte patterns that could be the displacement.

    referencing_addrs = {}  # string_name -> set of code VAs

    for block_start, block_end in code_blocks:
        block_size = block_end.getOffset() - block_start.getOffset() + 1
        if block_size > 20 * 1024 * 1024:  # skip blocks > 20MB to be safe
            print("  Skipping large block %s (%d MB)" % (
                block_start, block_size // (1024*1024)))
            continue

        try:
            data = bytearray(block_size)
            mem.getBytes(block_start, data)
        except Exception as e:
            print("  [WARN] Cannot read block %s: %s" % (block_start, e))
            continue

        block_start_offset = block_start.getOffset()

        # For each string VA, search for RIP-relative displacements
        for str_va, str_name in string_va_to_name.items():
            if str_name not in referencing_addrs:
                referencing_addrs[str_name] = set()

            # Scan through the code looking for displacement values
            # A LEA instruction with RIP-relative is typically 7 bytes:
            #   REX(1) + opcode(1) + ModRM(1) + disp32(4)
            # The disp32 is relative to the END of the instruction (IP + instr_len)
            # For a 7-byte instruction at addr A: target = A + 7 + disp32
            # So disp32 = target - A - 7

            for instr_len in [7, 6]:  # common LEA lengths
                for i in range(len(data) - 4):
                    instr_addr = block_start_offset + i
                    # disp32 is at offset (instr_len - 4) from instruction start
                    disp_offset = i + (instr_len - 4)
                    if disp_offset + 4 > len(data):
                        continue
                    disp32 = struct.unpack_from('<i', data, disp_offset)[0]
                    computed_target = (instr_addr + instr_len + disp32) & 0xffffffffffffffff
                    if computed_target == str_va:
                        # Potential reference! Verify by checking for LEA-like opcode
                        # REX.W prefix (0x48/0x4C) + LEA opcode (0x8D)
                        if instr_len == 7 and i >= 0:
                            byte0 = data[i]
                            byte1 = data[i+1] if i+1 < len(data) else 0
                            if byte0 in (0x48, 0x4C) and byte1 == 0x8D:
                                referencing_addrs[str_name].add(instr_addr)
                            # Also check for MOV with immediate (less common but possible)
                        elif instr_len == 6 and i >= 0:
                            byte0 = data[i]
                            if byte0 == 0x8D:  # LEA without REX
                                referencing_addrs[str_name].add(instr_addr)

    # Print results
    total_refs = 0
    for str_name, addrs in sorted(referencing_addrs.items()):
        if addrs:
            total_refs += len(addrs)
            print("  [REFS] '%s': %d references" % (str_name, len(addrs)))
            for a in sorted(addrs)[:5]:
                print("         @ 0x%016x" % a)
            if len(addrs) > 5:
                print("         ... +%d more" % (len(addrs) - 5))

    print("Phase 2 complete: %d total code references found" % total_refs)
    return referencing_addrs


def find_function_start(program, monitor, code_addr):
    """Walk backwards from code_addr to find the function prologue.
    Look for push rbp (0x55) or endbr64 (0xF3 0x0F 0x1E 0xFA)."""
    mem = program.getMemory()
    addr_space = program.getAddressFactory().getDefaultAddressSpace()

    # Search backwards up to 4KB for a function prologue
    for back in range(0, 4096):
        candidate = addr_space.getAddress(code_addr - back)
        try:
            b = mem.getByte(candidate) & 0xFF
            # push rbp = 0x55 (most common)
            if b == 0x55:
                # Verify: next byte should be mov rbp, rsp (48 89 e5) or similar
                try:
                    b1 = mem.getByte(candidate.add(1)) & 0xFF
                    b2 = mem.getByte(candidate.add(2)) & 0xFF
                    b3 = mem.getByte(candidate.add(3)) & 0xFF
                    if b1 == 0x48 and b2 == 0x89 and b3 == 0xe5:
                        return candidate.getOffset()
                except Exception:
                    pass
            # endbr64 = F3 0F 1E FA
            if b == 0xF3:
                try:
                    b1 = mem.getByte(candidate.add(1)) & 0xFF
                    b2 = mem.getByte(candidate.add(2)) & 0xFF
                    b3 = mem.getByte(candidate.add(3)) & 0xFF
                    if b1 == 0x0F and b2 == 0x1E and b3 == 0xFA:
                        return candidate.getOffset()
                except Exception:
                    pass
            # sub rsp, imm (48 83 EC xx or 48 81 EC xx xx xx xx) - alternative prologue
            if b == 0x48 and back > 0:
                try:
                    b1 = mem.getByte(candidate.add(1)) & 0xFF
                    b2 = mem.getByte(candidate.add(2)) & 0xFF
                    if b1 == 0x83 and b2 == 0xec:
                        return candidate.getOffset()
                except Exception:
                    pass
        except Exception:
            continue

    return None


def create_and_collect_functions(program, monitor, referencing_addrs):
    """Phase 3: Create functions at reference sites and walk call tree.
    Returns set of function objects to decompile."""

    print("=" * 70)
    print("Phase 3: Creating functions and walking call tree...")
    print("=" * 70)

    fm = program.getFunctionManager()
    listing = program.getListing()
    addr_space = program.getAddressFactory().getDefaultAddressSpace()

    # Map: function_entry_va -> (function_obj, set_of_strings_it_references)
    func_map = {}
    func_strings = {}  # entry_va -> set of string names

    for str_name, code_addrs in referencing_addrs.items():
        for code_addr in code_addrs:
            # Find the function start
            func_start = find_function_start(program, monitor, code_addr)
            if func_start is None:
                print("  [WARN] No prologue found near 0x%016x for '%s'" % (
                    code_addr, str_name))
                continue

            addr = addr_space.getAddress(func_start)

            # Ensure disassembly around this function
            try:
                end_addr = addr_space.getAddress(func_start + 0x2000)  # 8KB
                disassemble_range(program, monitor, addr, end_addr)
            except Exception:
                pass

            # Get or create function
            f = fm.getFunctionAt(addr)
            if f is None:
                cmd = CreateFunctionCmd(addr)
                try:
                    cmd.applyTo(program, monitor)
                    f = fm.getFunctionAt(addr)
                    if f:
                        print("  [CREATED] Function at 0x%016x for '%s'" % (
                            func_start, str_name))
                except Exception as e:
                    print("  [WARN] CreateFunction failed at 0x%016x: %s" % (
                        func_start, e))
                    continue

            if f is None:
                continue

            func_map[func_start] = f
            if func_start not in func_strings:
                func_strings[func_start] = set()
            func_strings[func_start].add(str_name)

    print("  Direct functions found: %d" % len(func_map))

    # Walk call tree CALL_TREE_DEPTH levels up and down
    all_funcs = dict(func_map)
    frontier = set(func_map.values())

    for depth in range(CALL_TREE_DEPTH):
        next_frontier = set()
        for f in frontier:
            # Callers
            try:
                for caller in f.getCallingFunctions():
                    entry = caller.getEntryPoint().getOffset()
                    if entry not in all_funcs:
                        all_funcs[entry] = caller
                        next_frontier.add(caller)
            except Exception:
                pass
            # Callees
            try:
                for callee in f.getCalledFunctions():
                    entry = callee.getEntryPoint().getOffset()
                    if entry not in all_funcs:
                        all_funcs[entry] = callee
                        next_frontier.add(callee)
            except Exception:
                pass
        frontier = next_frontier
        print("  Call tree depth %d: +%d functions (total %d)" % (
            depth + 1, len(frontier), len(all_funcs)))

    print("Phase 3 complete: %d total functions to decompile" % len(all_funcs))
    return all_funcs, func_strings


def decompile_functions(program, monitor, all_funcs, func_strings):
    """Phase 4: Decompile all collected functions."""

    print("=" * 70)
    print("Phase 4: Decompiling %d functions..." % len(all_funcs))
    print("=" * 70)

    decomp = DecompInterface()
    decomp_options = DecompileOptions()
    decomp_options.setDecompilerMaxTimeout(120)
    decomp.setOptions(decomp_options)
    decomp.openProgram(program)

    extracted = 0
    failed = 0
    results = []  # (addr, name, filename, strings_set, callers, callees, success)

    for addr_int in sorted(all_funcs.keys()):
        f = all_funcs[addr_int]
        short = short_name(addr_int)
        fname = f.getName()
        out_file = os.path.join(OUT_DIR, "decompiled_%s_%s.c" % (short, fname))

        # Determine which strings this function references (if any)
        strings_set = func_strings.get(addr_int, set())
        is_direct = len(strings_set) > 0

        try:
            res = decomp.decompileFunction(f, 120, monitor)
            if res and res.decompileCompleted():
                src = res.getDecompiledFunction().getC()
                callers = list(f.getCallingFunctions())
                callees = list(f.getCalledFunctions())

                with open(out_file, "w") as fh:
                    fh.write("// Extracted by Ghidra headless (ExtractGeomCryptPipeline.py)\n")
                    fh.write("// addr: 0x%016x  name: %s  size: %d\n" % (
                        addr_int, fname, f.getBody().getNumAddresses()))
                    fh.write("// scope: GEOM_CRYPT/HDD encryption pipeline\n")
                    if is_direct:
                        fh.write("// DIRECT REFERENCE to strings:\n")
                        for s in sorted(strings_set):
                            fh.write("//   \"%s\"\n" % s)
                    else:
                        fh.write("// INDIRECT (call-tree neighbor of direct function)\n")
                    fh.write("// callers (%d):\n" % len(callers))
                    for c in callers[:20]:
                        fh.write("//   %s @ 0x%016x\n" % (
                            c.getName(), c.getEntryPoint().getOffset()))
                    if len(callers) > 20:
                        fh.write("//   ... +%d more\n" % (len(callers) - 20))
                    fh.write("// callees (%d):\n" % len(callees))
                    for c in callees[:20]:
                        fh.write("//   %s @ 0x%016x\n" % (
                            c.getName(), c.getEntryPoint().getOffset()))
                    if len(callees) > 20:
                        fh.write("//   ... +%d more\n" % (len(callees) - 20))
                    fh.write("\n")
                    fh.write(src.encode('ascii', 'replace').decode('ascii'))

                extracted += 1
                results.append((addr_int, fname, os.path.basename(out_file),
                               strings_set, len(callers), len(callees), True))
                status = "DIRECT" if is_direct else "INDIRECT"
                print("[OK %s] 0x%016x %s -> %s (callers=%d, callees=%d)" % (
                    status, addr_int, fname, os.path.basename(out_file),
                    len(callers), len(callees)))
            else:
                failed += 1
                msg = ""
                if res:
                    msg = res.getErrorMessage() or ""
                results.append((addr_int, fname, "", strings_set, 0, 0, False))
                print("[DECOMP-FAIL] 0x%016x %s: %s" % (addr_int, fname, msg[:100]))
        except Exception as e:
            failed += 1
            results.append((addr_int, fname, "", strings_set, 0, 0, False))
            print("[EXC] 0x%016x %s: %s" % (addr_int, fname, str(e)))

    decomp.disposeProgram(program)
    print("Phase 4 complete: extracted=%d, failed=%d" % (extracted, failed))
    return results


def write_summary(string_locations, referencing_addrs, all_funcs, func_strings, results):
    """Write a comprehensive summary file."""
    summary_file = os.path.join(OUT_DIR, "_SUMMARY.txt")

    with open(summary_file, "w") as s:
        s.write("=" * 70 + "\n")
        s.write("GEOM_CRYPT Pipeline Extraction Summary\n")
        s.write("Generated by ExtractGeomCryptPipeline.py\n")
        s.write("=" * 70 + "\n\n")

        # String search results
        s.write("## String Search Results\n\n")
        for target in TARGET_STRINGS:
            vas = string_locations.get(target, [])
            if vas:
                s.write("[FOUND] \"%s\"\n" % target)
                for va in vas:
                    s.write("        VA: %s\n" % va)
            else:
                s.write("[NOT FOUND] \"%s\"\n" % target)
        s.write("\n")

        # Reference scan results
        s.write("## Code References Found\n\n")
        for str_name in sorted(referencing_addrs.keys()):
            addrs = referencing_addrs[str_name]
            if addrs:
                s.write("  \"%s\": %d refs\n" % (str_name, len(addrs)))
                for a in sorted(addrs):
                    s.write("    @ 0x%016x\n" % a)
        s.write("\n")

        # Functions extracted
        s.write("## Functions Extracted\n\n")
        s.write("Total: %d\n" % len(results))
        s.write("Successful: %d\n" % sum(1 for r in results if r[6]))
        s.write("Failed: %d\n\n" % sum(1 for r in results if not r[6]))

        # Direct functions (reference strings)
        s.write("### Direct (reference anchor strings):\n\n")
        for addr, name, filename, strings, callers, callees, ok in results:
            if strings and ok:
                s.write("  0x%016x  %s\n" % (addr, name))
                s.write("    file: %s\n" % filename)
                s.write("    strings: %s\n" % ", ".join(sorted(strings)))
                s.write("    callers: %d  callees: %d\n\n" % (callers, callees))

        # Indirect functions (call tree)
        s.write("### Indirect (call-tree neighbors):\n\n")
        for addr, name, filename, strings, callers, callees, ok in results:
            if not strings and ok:
                s.write("  0x%016x  %s -> %s  (callers=%d, callees=%d)\n" % (
                    addr, name, filename, callers, callees))

        s.write("\n")

        # Failed
        s.write("### Failed:\n\n")
        for addr, name, filename, strings, callers, callees, ok in results:
            if not ok:
                s.write("  0x%016x  %s  (FAILED)\n" % (addr, name))

    print("Summary written to: %s" % summary_file)
    return summary_file


def main():
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)

    program = currentProgram
    monitor = ConsoleTaskMonitor()

    print("=" * 70)
    print("ExtractGeomCryptPipeline.py")
    print("Program: %s" % program.getName())
    print("Image base: %s" % program.getImageBase())
    print("=" * 70)

    # Phase 1: Find strings
    string_locations = find_strings_in_memory(program)

    # Phase 2: Scan for code references
    referencing_addrs = scan_for_references(program, monitor, string_locations)

    # Phase 3: Create functions and walk call tree
    all_funcs, func_strings = create_and_collect_functions(
        program, monitor, referencing_addrs)

    if not all_funcs:
        print("=" * 70)
        print("WARNING: No functions found! Trying fallback approach...")
        print("=" * 70)
        # Fallback: use the known file offsets from the investigation plan
        # and compute VAs directly from the ELF base
        base = program.getImageBase().getOffset()
        fallback_offsets = {
            # Functions near the GEOM_CRYPT strings (estimated from string offsets)
            # The functions that LOG these strings must be in code nearby
            # String offsets are ~0xAExxxx, code should be in the same region
            0xaee641: "geom_crypt_eap_setup_vicinity",
            0xaee9af: "geom_crypt_apply_eap_vicinity",
            0xaee9d1: "geom_crypt_apply_xts_vicinity",
            0xaee9ef: "geom_crypt_apply_main_vicinity",
            0xaeea14: "geom_crypt_apply_ext_vicinity",
        }
        print("Fallback: scanning %d string vicinities for function prologues..." %
              len(fallback_offsets))
        # Search backwards from each string for function prologues in the
        # code section before the strings
        for file_off, label in fallback_offsets.items():
            string_va = base + file_off
            # Scan backwards from string for function prologues
            func_addr = find_function_start(program, monitor, string_va)
            if func_addr:
                print("  [FALLBACK] Prologue at 0x%016x for %s" % (func_addr, label))

    # Phase 4: Decompile
    results = decompile_functions(program, monitor, all_funcs, func_strings)

    # Write summary
    write_summary(string_locations, referencing_addrs, all_funcs, func_strings, results)

    print("=" * 70)
    print("ALL DONE. Output in: %s" % OUT_DIR)
    print("=" * 70)


main()
