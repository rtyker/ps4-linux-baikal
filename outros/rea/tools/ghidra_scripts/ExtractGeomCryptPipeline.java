// Ghidra headless script: Find and decompile all functions in the GEOM_CRYPT
// encryption pipeline of the PS4 Orbis kernel (memoriateste.bin / kmem_dump_1252.bin).
//
// Usage:
//   analyzeHeadless <project_loc> <project> \
//       -process kmem_dump_1252.bin -noanalysis \
//       -postScript ExtractGeomCryptPipeline.java \
//       -scriptPath /mnt/t/downloads/PS4/linux_project/consolidado/tools/ghidra_scripts \
//       -readOnly

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.app.decompiler.*;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.*;
import ghidra.program.model.symbol.*;
import ghidra.util.task.ConsoleTaskMonitor;

public class ExtractGeomCryptPipeline extends GhidraScript {

    private static final String OUT_DIR = "/mnt/t/downloads/PS4/linux_project/consolidado/decompiled/geom_crypt";

    private static final String[] TARGET_STRINGS = {
        "GEOM_CRYPT[%u]: eap key setup",
        "GEOM_CRYPT[%u]: applying eap key",
        "GEOM_CRYPT[%u]: applying XTS",
        "GEOM_CRYPT[%u]: applying main key 2",
        "GEOM_CRYPT[%u]: applying ext key",
        "SCE_EAP_HDD__KEY",
        "EAP_U00",
        "EAP_V00",
        "sceSblWrapHddEapPartitionKeyData",
        "sceSblGetEapInternalPartKeyAddSign",
        "sceSblAuthMgrAddEEkc ",
        "sceSblAuthMgrAddEEkc2",
        "sceSblAuthMgrAddEEkc3",
        "sceSblAuthMgrDeleteEEkc",
        "sceSblKeymgrSmCallfuncWithID",
        "sceSblKeymgrLockKey",
        "geom_crypt.c"
    };

    // Fallback file offsets from static analysis of memoriateste.bin (VA = 0xffffffffdc350000 + offset)
    private static final long[] FALLBACK_OFFSETS = {
        0x00aee641L, // eap key setup
        0x00aee9afL, // applying eap key
        0x00aeea14L, // applying ext key
        0x00aee9efL, // applying main key 2
        0x00aee9d1L, // applying XTS
        0x00ae7f30L, // SCE_EAP_HDD__KEY
        0x00aeb434L, // sceSblWrapHddEapPartitionKeyData
        0x00aeb474L, // sceSblGetEapInternalPartKeyAddSign
        0x00aed53eL, // sceSblAuthMgrAddEEkc
        0x00aed569L, // sceSblAuthMgrAddEEkc2
        0x00aed4d6L, // sceSblAuthMgrAddEEkc3
        0x00aed510L, // sceSblAuthMgrDeleteEEkc
        0x00ae8bc5L, // sceSblKeymgrSmCallfuncWithID
        0x00b17279L, // sceSblKeymgrLockKey
        0x00aee8f2L  // geom_crypt.c
    };

    @Override
    protected void run() throws Exception {
        File outDir = new File(OUT_DIR);
        outDir.mkdirs();

        Memory memory = currentProgram.getMemory();
        Listing listing = currentProgram.getListing();
        FunctionManager fm = currentProgram.getFunctionManager();
        AddressFactory addrFactory = currentProgram.getAddressFactory();
        AddressSpace defaultSpace = addrFactory.getDefaultAddressSpace();
        ConsoleTaskMonitor monitor = new ConsoleTaskMonitor();

        println("======================================================================");
        println("ExtractGeomCryptPipeline (Java): Starting GEOM_CRYPT RE extraction...");
        println("Program: " + currentProgram.getName());
        println("Image Base: " + currentProgram.getImageBase());
        println("======================================================================");

        Map<String, List<Address>> stringLocations = new HashMap<>();
        Set<Address> codeReferencingVAs = new HashSet<>();
        Map<Address, Set<String>> addressToStringsMap = new HashMap<>();

        // Phase 1: Search for anchor strings in memory
        println("\n--- Phase 1: Searching for " + TARGET_STRINGS.length + " anchor strings in memory ---");
        for (String target : TARGET_STRINGS) {
            List<Address> foundAddrs = new ArrayList<>();
            byte[] bytes = target.getBytes(StandardCharsets.US_ASCII);

            for (MemoryBlock block : memory.getBlocks()) {
                if (!block.isRead()) continue;
                Address start = block.getStart();
                Address end = block.getEnd();

                Address curr = start;
                while (curr != null && curr.compareTo(end) < 0) {
                    Address match = memory.findBytes(curr, end, bytes, null, true, monitor);
                    if (match == null) break;
                    foundAddrs.add(match);
                    println("  [FOUND] \"" + target + "\" at VA " + match);
                    curr = match.add(1);
                }
            }
            stringLocations.put(target, foundAddrs);
        }

        // Phase 2: Scan executable code blocks for RIP-relative LEA instructions
        println("\n--- Phase 2: Scanning executable code for references to strings ---");
        Map<Long, String> vaToStringNameMap = new HashMap<>();
        for (Map.Entry<String, List<Address>> entry : stringLocations.entrySet()) {
            for (Address addr : entry.getValue()) {
                vaToStringNameMap.put(addr.getOffset(), entry.getKey());
            }
        }

        // Also add fallback string VAs just in case
        long baseVA = currentProgram.getImageBase().getOffset();
        for (long off : FALLBACK_OFFSETS) {
            long va = baseVA + off;
            if (!vaToStringNameMap.containsKey(va)) {
                vaToStringNameMap.put(va, "fallback_off_0x" + Long.toHexString(off));
            }
        }

        for (MemoryBlock block : memory.getBlocks()) {
            if (!block.isExecute()) continue;
            Address blockStart = block.getStart();
            long blockSize = block.getSize();
            if (blockSize > 25 * 1024 * 1024) continue; // skip massive blocks

            println("  Scanning executable block: " + blockStart + " - " + block.getEnd() + " (" + (blockSize / 1024 / 1024) + " MB)");
            byte[] blockData = new byte[(int) blockSize];
            try {
                block.getBytes(blockStart, blockData);
            } catch (Exception e) {
                println("  Failed to read block bytes: " + e.getMessage());
                continue;
            }

            long blockStartOff = blockStart.getOffset();
            int dataLen = blockData.length;

            for (Map.Entry<Long, String> entry : vaToStringNameMap.entrySet()) {
                long strVA = entry.getKey();
                String strName = entry.getValue();

                int foundForThisString = 0;

                // Check LEA instructions (lengths 7 and 6 bytes)
                for (int instrLen : new int[]{7, 6}) {
                    int dispOffsetFromInstr = instrLen - 4;
                    for (int i = 0; i <= dataLen - instrLen; i++) {
                        int dispPos = i + dispOffsetFromInstr;
                        int disp32 = (blockData[dispPos] & 0xFF)
                                | ((blockData[dispPos + 1] & 0xFF) << 8)
                                | ((blockData[dispPos + 2] & 0xFF) << 16)
                                | ((blockData[dispPos + 3]) << 24);

                        long instrAddr = blockStartOff + i;
                        long computedTarget = instrAddr + instrLen + disp32;

                        if (computedTarget == strVA) {
                            // Check opcode pattern for LEA (48 8d / 4c 8d / 8d)
                            byte b0 = blockData[i];
                            byte b1 = (i + 1 < dataLen) ? blockData[i + 1] : 0;

                            boolean isLea = (instrLen == 7 && (b0 == (byte) 0x48 || b0 == (byte) 0x4C) && b1 == (byte) 0x8D)
                                         || (instrLen == 6 && b0 == (byte) 0x8D);

                            if (isLea) {
                                Address codeVA = defaultSpace.getAddress(instrAddr);
                                codeReferencingVAs.add(codeVA);
                                addressToStringsMap.computeIfAbsent(codeVA, k -> new HashSet<>()).add(strName);
                                foundForThisString++;
                            }
                        }
                    }
                }
                if (foundForThisString > 0) {
                    println("    Found " + foundForThisString + " code refs to \"" + strName + "\" (VA 0x" + Long.toHexString(strVA) + ")");
                }
            }
        }

        println("  Total code reference VAs found: " + codeReferencingVAs.size());

        // Phase 3: Find function entry points by searching backwards for prologues
        println("\n--- Phase 3: Finding function prologues and creating functions ---");
        Set<Address> targetFuncEntries = new HashSet<>();
        Map<Address, Set<String>> funcToStringsMap = new HashMap<>();

        for (Address codeVA : codeReferencingVAs) {
            Address funcEntry = findPrologue(memory, codeVA);
            if (funcEntry != null) {
                targetFuncEntries.add(funcEntry);
                Set<String> stringsAtCode = addressToStringsMap.get(codeVA);
                if (stringsAtCode != null) {
                    funcToStringsMap.computeIfAbsent(funcEntry, k -> new HashSet<>()).addAll(stringsAtCode);
                }
            }
        }

        // Also search fallback offsets directly
        for (long off : FALLBACK_OFFSETS) {
            Address strVA = defaultSpace.getAddress(baseVA + off);
            Address funcEntry = findPrologue(memory, strVA);
            if (funcEntry != null) {
                targetFuncEntries.add(funcEntry);
                funcToStringsMap.computeIfAbsent(funcEntry, k -> new HashSet<>()).add("fallback_vicinity_0x" + Long.toHexString(off));
            }
        }

        println("  Function entry points identified: " + targetFuncEntries.size());

        // Ensure disassembly around function entries
        for (Address entry : targetFuncEntries) {
            if (listing.getInstructionAt(entry) == null) {
                try {
                    Address end = entry.add(2048);
                    DisassembleCommand dcmd = new DisassembleCommand(entry, new AddressSet(entry, end), false);
                    dcmd.applyTo(currentProgram, monitor);
                } catch (Exception e) {
                    // ignore
                }
            }
        }

        // Create functions
        Set<Function> funcsToDecompile = new HashSet<>();
        for (Address entry : targetFuncEntries) {
            Function f = fm.getFunctionAt(entry);
            if (f == null) {
                CreateFunctionCmd cmd = new CreateFunctionCmd(entry);
                if (cmd.applyTo(currentProgram, monitor)) {
                    f = fm.getFunctionAt(entry);
                }
            }
            if (f != null) {
                funcsToDecompile.add(f);
            }
        }

        // Include callers/callees (1 level)
        Set<Function> expandedFuncs = new HashSet<>(funcsToDecompile);
        for (Function f : funcsToDecompile) {
            try {
                expandedFuncs.addAll(f.getCallingFunctions(monitor));
                expandedFuncs.addAll(f.getCalledFunctions(monitor));
            } catch (Exception e) {
                // ignore
            }
        }
        println("  Total functions to decompile (including 1-level callers/callees): " + expandedFuncs.size());

        // Phase 4: Decompile functions
        println("\n--- Phase 4: Decompiling functions ---");
        DecompInterface decomp = new DecompInterface();
        DecompileOptions options = new DecompileOptions();
        options.setDefaultTimeout(120);
        decomp.setOptions(options);
        decomp.openProgram(currentProgram);

        int extracted = 0;
        int failed = 0;

        File summaryFile = new File(outDir, "_SUMMARY.txt");
        try (PrintWriter sumPw = new PrintWriter(new FileWriter(summaryFile))) {
            sumPw.println("======================================================================");
            sumPw.println("GEOM_CRYPT Extraction Summary");
            sumPw.println("======================================================================");
            sumPw.println("Target strings searched: " + TARGET_STRINGS.length);
            sumPw.println("Functions identified:   " + expandedFuncs.size());
            sumPw.println();

            for (Function f : expandedFuncs) {
                Address entry = f.getEntryPoint();
                long addrInt = entry.getOffset();
                String shortName = String.format("%08x", addrInt & 0xffffffffL);
                File outFile = new File(outDir, "decompiled_" + shortName + "_" + f.getName() + ".c");

                Set<String> stringsReferenced = funcToStringsMap.get(entry);
                boolean isDirect = (stringsReferenced != null && !stringsReferenced.isEmpty());

                try {
                    DecompileResults res = decomp.decompileFunction(f, 120, monitor);
                    if (res != null && res.decompileCompleted()) {
                        String src = res.getDecompiledFunction().getC();
                        List<Function> callers = new ArrayList<>(f.getCallingFunctions(monitor));
                        List<Function> callees = new ArrayList<>(f.getCalledFunctions(monitor));

                        try (PrintWriter pw = new PrintWriter(new FileWriter(outFile))) {
                            pw.println("// Extracted by Ghidra headless (ExtractGeomCryptPipeline.java)");
                            pw.println("// addr: 0x" + String.format("%016x", addrInt) + "  name: " + f.getName() + "  size: " + f.getBody().getNumAddresses());
                            pw.println("// type: " + (isDirect ? "DIRECT (references anchor strings)" : "INDIRECT (neighbor in call tree)"));
                            if (isDirect) {
                                pw.println("// strings: " + String.join(", ", stringsReferenced));
                            }
                            pw.println("// callers (" + callers.size() + "):");
                            for (int i = 0; i < Math.min(callers.size(), 15); i++) {
                                pw.println("//   " + callers.get(i).getName() + " @ 0x" + String.format("%016x", callers.get(i).getEntryPoint().getOffset()));
                            }
                            pw.println("// callees (" + callees.size() + "):");
                            for (int i = 0; i < Math.min(callees.size(), 15); i++) {
                                pw.println("//   " + callees.get(i).getName() + " @ 0x" + String.format("%016x", callees.get(i).getEntryPoint().getOffset()));
                            }
                            pw.println();
                            pw.print(src);
                        }

                        extracted++;
                        println("  [OK] 0x" + String.format("%016x", addrInt) + " " + f.getName() + " -> " + outFile.getName());
                        sumPw.println("0x" + String.format("%016x", addrInt) + "  " + f.getName() + "  (" + (isDirect ? "DIRECT: " + String.join(", ", stringsReferenced) : "INDIRECT") + ")");
                    } else {
                        failed++;
                        println("  [DECOMP-FAIL] 0x" + String.format("%016x", addrInt) + " " + f.getName());
                        sumPw.println("0x" + String.format("%016x", addrInt) + "  " + f.getName() + "  [DECOMP-FAIL]");
                    }
                } catch (Exception e) {
                    failed++;
                    println("  [EXC] 0x" + String.format("%016x", addrInt) + " " + e.getMessage());
                }
            }
        }

        decomp.dispose();

        println("======================================================================");
        println("SUMMARY: Extracted=" + extracted + "  Failed=" + failed + "  Total=" + expandedFuncs.size());
        println("Output files written to: " + OUT_DIR);
        println("======================================================================");
    }

    private Address findPrologue(Memory memory, Address start) {
        long startOff = start.getOffset();
        AddressSpace space = start.getAddressSpace();

        // Search backwards up to 4KB for push rbp (0x55 0x48 0x89 0xe5) or endbr64 (0xf3 0x0f 0x1e 0xfa)
        for (int back = 0; back < 4096; back++) {
            try {
                Address cand = space.getAddress(startOff - back);
                byte b0 = memory.getByte(cand);

                // push rbp = 0x55
                if (b0 == (byte) 0x55) {
                    byte b1 = memory.getByte(cand.add(1));
                    byte b2 = memory.getByte(cand.add(2));
                    byte b3 = memory.getByte(cand.add(3));
                    if (b1 == (byte) 0x48 && b2 == (byte) 0x89 && b3 == (byte) 0xE5) {
                        return cand;
                    }
                }

                // endbr64 = F3 0F 1E FA
                if (b0 == (byte) 0xF3) {
                    byte b1 = memory.getByte(cand.add(1));
                    byte b2 = memory.getByte(cand.add(2));
                    byte b3 = memory.getByte(cand.add(3));
                    if (b1 == (byte) 0x0F && b2 == (byte) 0x1E && b3 == (byte) 0xFA) {
                        return cand;
                    }
                }
            } catch (Exception e) {
                // out of bounds or memory unreadable
            }
        }
        return null;
    }
}
