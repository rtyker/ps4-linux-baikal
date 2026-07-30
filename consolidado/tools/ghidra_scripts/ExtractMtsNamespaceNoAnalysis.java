// Ghidra headless script: cria funções no namespace MTS/GBE/ICC/glue
// e decompila cada uma. Versão Java para rodar com analyzeHeadless sem PyGhidra.
// Uso:
//   analyzeHeadless <project_loc> <project> \
//       -import kmem_dump_1252.bin -noanalysis -overwrite \
//       -postScript ExtractMtsNamespaceNoAnalysis.java \
//       -scriptPath /path/to/ghidra_scripts

//@category PS4-MTS

import java.io.*;
import java.util.*;
import java.util.regex.Pattern;
import java.util.regex.Matcher;

import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.app.decompiler.*;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.*;
import ghidra.program.model.lang.Register;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
import ghidra.util.task.ConsoleTaskMonitor;

public class ExtractMtsNamespaceNoAnalysis extends GhidraScript {

    private static final String OUT_DIR = "/workspace/consolidado/decompiled/extracted";
    private static final String[] EXISTING_DIRS = {
        "/workspace/consolidado/decompiled",
        "/workspace/consolidado/decompiled/legacy_raiz",
    };

    // Endereços-alvo — atualizado 2026-07-30 com árvore de gbe_phy_ctrl (dc5a44c0)
    private static final long[] TARGET_ADDRS = {
        // ===== MTS driver - lacunas validadas =====
        0xffffffffdc5a2840L,  // MDIO read high word (bits 31:16)
        0xffffffffdc5a2950L,  // MDIO write opcode 0x2000
        0xffffffffdc5a4950L,  // trigger BAR0+0x1c = 0x80000000
        0xffffffffdc5a4e90L,  // relacionado ao RMU/dc5a5200
        0xffffffffdc5a5050L,  // próximo do trigger
        0xffffffffdc5a5200L,  // RMU sub-header 0x9807
        0xffffffffdc5a6290L,  // sub-rotina vista em chamada

        // ===== MTS helpers =====
        0xffffffffdc5ba8d0L,  // chamado por dc718eb0 (aloca BARs)
        0xffffffffdc5baa30L,  // chamado por dc5a0070 (cria ifnet)

        // ===== Glue/PCIe sub-funções =====
        0xffffffffdc6dfb60L,  // primitiva reset glue (0x4000)
        0xffffffffdc7187a0L,  // glue read
        0xffffffffdc7187d0L,  // glue read
        0xffffffffdc718800L,  // glue write

        // ===== ICC =====
        0xffffffffdc3f5bd0L,  // wrapper icc_query(4, 0x38)
        0xffffffffdc574150L,  // handlers ICC (6x em dc528760)
        0xffffffffdc528ef0L,  // handler 4/0x38 = GBE power-on

        // ===== GBE clk/phy =====
        0xffffffffdc529ed0L,  // lacuna GBE
        0xffffffffdc529f40L,  // lacuna GBE
        0xffffffffdc52a4f0L,  // lacuna GBE

        // ===== GBE PHY Control Thread (gbe_phy_ctrl / dc5a44c0) =====
        0xffffffffdc5a44c0L,  // gbe_phy_ctrl - thread principal PHY
        0xffffffffdc524770L,  // chamado por dc5a44c0 (init)
        0xffffffffdc6c8300L,  // mutex lock - chamado múltiplas vezes
        0xffffffffdc6c85b0L,  // mutex unlock
        0xffffffffdc48fe00L,  // wait/sleep com timeout
        0xffffffffdcabbf00L,  // error handler 1
        0xffffffffdcabbe70L,  // error handler 2
        0xffffffffdc460780L,  // panic/fatal
        0xffffffffdc5a2680L,  // PHY MDIO read? (2x em dc5a44c0 linhas 78-79)
        0xffffffffdc5a2840L,  // MDIO read high word (já listado acima)
        0xffffffffdc524510L,  // cleanup/exit thread

        // ===== Busca SAMU =====
        0xffffffffdc524a80L,  // potencial call SAMU
    };

    private static final Pattern ADDR_RE = Pattern.compile("0xffffffff(dc[0-9a-f]{6}|dc[0-9a-f]{5})");

    private Set<Long> existingAddrs = new HashSet<>();
    private int extracted = 0, skipped = 0, failed = 0, created = 0, notInMem = 0;

    @Override
    protected void run() throws Exception {
        // Garantir diretório de saída
        new File(OUT_DIR).mkdirs();

        // Escanear endereços já decompilados
        scanExisting();

        FunctionManager fm = currentProgram.getFunctionManager();
        Listing listing = currentProgram.getListing();
        ConsoleTaskMonitor monitor = new ConsoleTaskMonitor();

        // Disassemble ranges necessários
        AddressFactory addrFactory = currentProgram.getAddressFactory();
        AddressSpace defaultSpace = addrFactory.getDefaultAddressSpace();
        AddressSet disasmNeeded = new AddressSet();
        for (long addrInt : TARGET_ADDRS) {
            Address addr = defaultSpace.getAddress(addrInt);
            if (listing.getInstructionAt(addr) == null) {
                Address end = defaultSpace.getAddress(addrInt + 255);
                disasmNeeded.addRange(addr, end);
            }
        }
        if (!disasmNeeded.isEmpty()) {
            println("Disassembling " + disasmNeeded.getNumAddressRanges() + " ranges...");
            for (AddressRange rng : disasmNeeded) {
                Address start = rng.getMinAddress();
                Address end = rng.getMaxAddress();
                try {
                    DisassembleCommand dcmd = new DisassembleCommand(start, new AddressSet(start, end), false);
                    dcmd.applyTo(currentProgram, monitor);
                } catch (Exception e) {
                    println("disasm fail @ " + start + ": " + e.getMessage());
                }
            }
        }

        // Decompiler
        DecompInterface decomp = new DecompInterface();
        DecompileOptions options = new DecompileOptions();
        options.setDefaultTimeout(60);
        decomp.setOptions(options);
        decomp.openProgram(currentProgram);

        println("======================================================================");
        println("ExtractMtsNamespaceNoAnalysis (Java): " + TARGET_ADDRS.length + " enderecos alvo");
        println("======================================================================");

        for (long addrInt : TARGET_ADDRS) {
            Address addr = defaultSpace.getAddress(addrInt);

            // Verifica se está na memória
            if (!currentProgram.getMemory().contains(addr)) {
                notInMem++;
                println("[NOT-IN-MEM] 0x" + String.format("%016x", addrInt));
                continue;
            }

            String shortName = String.format("%08x", addrInt & 0xffffffffL);

            // Pula se já decompilado
            if (isExisting(addrInt)) {
                skipped++;
                println("[SKIP-EXIST] 0x" + String.format("%016x", addrInt) + " " + shortName);
                continue;
            }

            File outFile = new File(OUT_DIR, "decompiled_" + shortName + ".txt");
            if (outFile.exists()) {
                skipped++;
                continue;
            }

            // Obtém ou cria função
            Function func = fm.getFunctionAt(addr);
            if (func == null) {
                CreateFunctionCmd createCmd = new CreateFunctionCmd(addr);
                try {
                    boolean applied = createCmd.applyTo(currentProgram, monitor);
                    if (applied) {
                        created++;
                        func = fm.getFunctionAt(addr);
                    } else {
                        failed++;
                        println("[CREATE-FAIL] 0x" + String.format("%016x", addrInt));
                        continue;
                    }
                } catch (Exception e) {
                    failed++;
                    println("[CREATE-EXC] 0x" + String.format("%016x", addrInt) + " " + e.getMessage());
                    continue;
                }
            }

            if (func == null) {
                failed++;
                println("[NO-FUNC] 0x" + String.format("%016x", addrInt));
                continue;
            }

            try {
                DecompileResults res = decomp.decompileFunction(func, 90, monitor);
                if (res != null && res.decompileCompleted()) {
                    String src = res.getDecompiledFunction().getC();
                    List<Function> callers = new ArrayList<>(func.getCallingFunctions(monitor));
                    List<Function> callees = new ArrayList<>(func.getCalledFunctions(monitor));

                    try (PrintWriter pw = new PrintWriter(new FileWriter(outFile))) {
                        pw.println("// Extraido por Ghidra headless (ExtractMtsNamespaceNoAnalysis.java)");
                        pw.println("// addr: 0x" + String.format("%016x", addrInt) +
                                   "  name: " + func.getName() +
                                   "  size: " + func.getBody().getNumAddresses());
                        pw.println("// escopo: lacuna MTS/GBE/ICC/glue identificada em testes ao vivo");
                        pw.println("// chamadores (" + callers.size() + "):");
                        for (int i = 0; i < Math.min(callers.size(), 20); i++) {
                            Function c = callers.get(i);
                            pw.println("//   " + c.getName() + " @ 0x" + String.format("%016x", c.getEntryPoint().getOffset()));
                        }
                        if (callers.size() > 20) {
                            pw.println("//   ... +" + (callers.size() - 20) + " mais");
                        }
                        pw.println("// chamadas (" + callees.size() + "):");
                        for (int i = 0; i < Math.min(callees.size(), 20); i++) {
                            Function c = callees.get(i);
                            pw.println("//   " + c.getName() + " @ 0x" + String.format("%016x", c.getEntryPoint().getOffset()));
                        }
                        if (callees.size() > 20) {
                            pw.println("//   ... +" + (callees.size() - 20) + " mais");
                        }
                        pw.println();
                        pw.print(src);
                    }

                    extracted++;
                    println("[OK] 0x" + String.format("%016x", addrInt) +
                            " -> " + outFile.getName() +
                            "  (callers=" + callers.size() + ", callees=" + callees.size() + ")");
                } else {
                    failed++;
                    println("[DECOMP-FAIL] 0x" + String.format("%016x", addrInt));
                }
            } catch (Exception e) {
                failed++;
                println("[EXC] 0x" + String.format("%016x", addrInt) + " " + e.getMessage());
            }
        }

        decomp.dispose();

        // Summary
        println("======================================================================");
        String summaryStr = String.format(
            "FINAL: extracted=%d  skipped=%d  failed=%d  created=%d  notInMem=%d",
            extracted, skipped, failed, created, notInMem);
        println(summaryStr);

        File summaryFile = new File(OUT_DIR, "_extraction_summary.txt");
        try (PrintWriter pw = new PrintWriter(new FileWriter(summaryFile))) {
            pw.println("Resumo ExtractMtsNamespaceNoAnalysis.java");
            pw.println("==================================================");
            pw.println("Enderecos-alvo:     " + TARGET_ADDRS.length);
            pw.println("Extraidos agora:    " + extracted);
            pw.println("Skipped (ja existiam): " + skipped);
            pw.println("Falhas (decomp):    " + failed);
            pw.println("Fora da MEM:        " + notInMem);
            pw.println("Funcoes criadas:    " + created);
        }
    }

    private void scanExisting() {
        for (String dirName : EXISTING_DIRS) {
            File dir = new File(dirName);
            if (!dir.isDirectory()) continue;
            for (File f : dir.listFiles()) {
                if (!f.getName().endsWith(".txt")) continue;
                try (BufferedReader br = new BufferedReader(new FileReader(f))) {
                    char[] buf = new char[2048];
                    int n = br.read(buf, 0, 2048);
                    if (n > 0) {
                        String head = new String(buf, 0, n);
                    java.util.regex.Matcher m = ADDR_RE.matcher(head);
                        if (m.find()) {
                            long v = Long.parseLong(m.group(1), 16);
                            existingAddrs.add(v);
                        }
                    }
                } catch (Exception e) {
                    // skip
                }
            }
        }
    }

    private boolean isExisting(long addrInt) {
        int low20 = (int)(addrInt & 0xfffff);
        int low24 = (int)(addrInt & 0xffffff);
        int low16 = (int)(addrInt & 0xffff);
        return existingAddrs.contains((long)low20) ||
               existingAddrs.contains((long)low24) ||
               existingAddrs.contains((long)low16);
    }
}