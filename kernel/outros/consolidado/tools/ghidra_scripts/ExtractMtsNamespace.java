// Ghidra headless script (Java) - extrai decompilação C de funções MTS/GBE/ICC/glue
// sem dependencia de Python/PyGhidra.
//
// Uso:
//   analyzeHeadless <project_loc> <project> -process kmem_dump_1252.bin \
//       -postScript ExtractMtsNamespace.java \
//       -scriptPath /mnt/t/downloads/PS4/linux_in_ps4/consolidado/tools/ghidra_scripts \
//       -readOnly -noanalysis
//
//@category PS4-MTS
//@author opencode-automation

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileOptions;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.decompiler.DecompiledFunction;
import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressFactory;
import ghidra.program.model.address.AddressSet;
import ghidra.program.model.address.AddressRange;
import ghidra.util.task.ConsoleTaskMonitor;
import ghidra.util.task.TaskMonitor;

import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public class ExtractMtsNamespace extends GhidraScript {

    private static final String OUT_DIR = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/decompiled/extracted";

    // Endereços-alvo das LACUNAS (funções ainda não decompiladas, validadas em testes ao vivo).
    // Para adicionar nova função: inserir endereço aqui.
    private static final long[] TARGET_ADDRS = {
        // ===== MTS driver - lacunas validadas em test_history =====
        0xffffffffdc5a2840L, // MDIO read high word
        0xffffffffdc5a2950L, // MDIO write opcode 0x2000
        0xffffffffdc5a4950L, // gatilho BAR0+0x1c = 0x80000000
        0xffffffffdc5a4e90L, // relacionado RMU
        0xffffffffdc5a5050L, // provável pós-trigger
        0xffffffffdc5a5200L, // RMU sub-header 0x9807
        0xffffffffdc5a6290L, // sub-rotina
        // ===== MTS helpers =====
        0xffffffffdc5ba8d0L, // aloca BARs
        0xffffffffdc5baa30L, // cria ifnet
        // ===== Glue/PCIe sub-funções =====
        0xffffffffdc6dfb60L, // primitiva reset glue
        0xffffffffdc7187a0L, 0xffffffffdc7187d0L, 0xffffffffdc718800L, // glue read/write
        // ===== ICC =====
        0xffffffffdc3f5bd0L, // wrapper icc_query(4, 0x38) FUNDAMENTAL
        0xffffffffdc574150L, // registra handlers ICC
        0xffffffffdc528ef0L, // handler 4/0x38 GBE power-on
        // ===== GBE clk/phy =====
        0xffffffffdc529ed0L, 0xffffffffdc529f40L, 0xffffffffdc52a4f0L,
    };

    @Override
    public void run() throws Exception {
        File outDir = new File(OUT_DIR);
        if (!outDir.exists()) {
            outDir.mkdirs();
        }

        DecompInterface decomp = new DecompInterface();
        DecompileOptions opts = new DecompileOptions();
        opts.setDecompilerMaxTimeout(60);
        decomp.setOptions(opts);
        decomp.openProgram(currentProgram);

        FunctionManager fm = currentProgram.getFunctionManager();
        Listing listing = currentProgram.getListing();
        AddressFactory af = currentProgram.getAddressFactory();
        TaskMonitor monitor = getMonitor();

        int extracted = 0, skipped = 0, failed = 0, created = 0, notInMem = 0;

        println("========================================================");
        println("ExtractMtsNamespace (Java): " + TARGET_ADDRS.length + " enderecos alvo");
        println("========================================================");

        for (long addrInt : TARGET_ADDRS) {
            Address addr = af.getDefaultAddressSpace().getAddress(addrInt);

            // Verifica se endereço existe na memoria
            if (!currentProgram.getMemory().contains(addr)) {
                notInMem++;
                println("[NOT-IN-MEM] 0x" + Long.toHexString(addrInt));
                continue;
            }

            String shortName = String.format("%016x", addrInt).substring(8);

            // Tenta obter função existente
            Function f = fm.getFunctionAt(addr);
            if (f == null) {
                // Disassemble em torno do endereço (256 bytes)
                Address endAddr = af.getDefaultAddressSpace().getAddress(addrInt + 255);
                AddressSet set = new AddressSet(addr, endAddr);
                DisassembleCommand disasm = new DisassembleCommand(set, false);
                disasm.enableCodeAnalysis(false);
                disasm.applyTo(currentProgram, monitor);

                // Agora tenta criar função
                CreateFunctionCmd cmd = new CreateFunctionCmd(addr);
                if (cmd.applyTo(currentProgram, monitor)) {
                    created++;
                    f = fm.getFunctionAt(addr);
                } else {
                    failed++;
                    println("[CREATE-FAIL] 0x" + Long.toHexString(addrInt) + " " + cmd.getStatusMsg());
                    continue;
                }
            }

            if (f == null) {
                failed++;
                println("[NO-FUNC] 0x" + Long.toHexString(addrInt));
                continue;
            }

            String outFileName = "decompiled_" + shortName + ".txt";
            File outFile = new File(outDir, outFileName);
            if (outFile.exists()) {
                skipped++;
                continue;
            }

            try {
                DecompileResults res = decomp.decompileFunction(f, 90, monitor);
                if (res != null && res.decompileCompleted()) {
                    DecompiledFunction df = res.getDecompiledFunction();
                    String src = df.getC();

                    PrintWriter pw = new PrintWriter(new FileWriter(outFile));
                    pw.println("// Extraido por Ghidra headless (ExtractMtsNamespace.java)");
                    pw.println("// addr: 0x" + Long.toHexString(addrInt) + "  name: " + f.getName()
                            + "  size: " + f.getBody().getNumAddresses());
                    pw.println("// escopo: lacuna MTS/GBE/ICC/glue identificada em testes ao vivo");
                    pw.println("// chamadores (" + f.getCallingFunctions().size() + "):");
                    int cc = 0;
                    for (Function c : f.getCallingFunctions()) {
                        if (cc < 20) {
                            pw.println("//   " + c.getName() + " @ 0x" + Long.toHexString(c.getEntryPoint().getOffset()));
                        }
                        cc++;
                    }
                    if (cc > 20) pw.println("//   ... +" + (cc - 20) + " mais");
                    pw.println("// chamadas (" + f.getCalledFunctions().size() + "):");
                    int cd = 0;
                    for (Function c : f.getCalledFunctions()) {
                        if (cd < 20) {
                            pw.println("//   " + c.getName() + " @ 0x" + Long.toHexString(c.getEntryPoint().getOffset()));
                        }
                        cd++;
                    }
                    if (cd > 20) pw.println("//   ... +" + (cd - 20) + " mais");
                    pw.println();
                    pw.println(src);
                    pw.close();

                    extracted++;
                    println("[OK] 0x" + Long.toHexString(addrInt) + " -> " + outFileName
                            + "  callers=" + f.getCallingFunctions().size()
                            + "  callees=" + f.getCalledFunctions().size());
                } else {
                    failed++;
                    println("[DECOMP-FAIL] 0x" + Long.toHexString(addrInt));
                }
            } catch (Exception e) {
                failed++;
                println("[EXC] 0x" + Long.toHexString(addrInt) + " " + e.getMessage());
            }
        }

        decomp.disposeProgram(currentProgram);

        File summary = new File(outDir, "_extraction_summary.txt");
        try (PrintWriter s = new PrintWriter(new FileWriter(summary))) {
            s.println("Resumo ExtractMtsNamespace.java");
            s.println("==================================================");
            s.println("Enderecos-alvo:           " + TARGET_ADDRS.length);
            s.println("Extraidos agora:          " + extracted);
            s.println("Skipped (ja existiam):    " + skipped);
            s.println("Falhas (decomp):          " + failed);
            s.println("Fora da_MEM do program:   " + notInMem);
            s.println("Funcoes criadas (CreateFunctionCmd): " + created);
        }
        println("========================================================");
        println("FINAL: extracted=" + extracted + "  skipped=" + skipped
                + "  failed=" + failed + "  created=" + created + "  notInMem=" + notInMem);
    }
}
