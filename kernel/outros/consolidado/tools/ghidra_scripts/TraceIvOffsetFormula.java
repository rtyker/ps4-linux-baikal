import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.address.*;
import ghidra.program.model.listing.*;

public class TraceIvOffsetFormula extends GhidraScript {
    @Override
    public void run() throws Exception {
        println("=== TraceIvOffsetFormula.java starting ===");
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);

        long[] addrs = {
            0xffffffffdc9a40d0L, // g_crypt_create_provider
            0xffffffffdc9a1ce0L, // g_crypt_taste
            0xffffffffdc8dabaeL, // g_part_gpt
            0xffffffffdc8dab50L, // g_part_gpt_create_provider
            0xffffffffdc8d9e30L  // g_part_gpt_taste / init
        };

        AddressFactory af = currentProgram.getAddressFactory();
        FunctionManager fm = currentProgram.getFunctionManager();

        for (long va : addrs) {
            Address addr = af.getDefaultAddressSpace().getAddress(va);
            Function f = fm.getFunctionAt(addr);
            if (f == null) {
                f = fm.getFunctionContaining(addr);
            }
            if (f != null) {
                println("Found function: " + f.getName() + " at " + f.getEntryPoint());
                DecompileResults res = decomp.decompileFunction(f, 30, monitor);
                if (res != null && res.getDecompiledFunction() != null) {
                    String code = res.getDecompiledFunction().getC();
                    println("--- C Code for 0x" + Long.toHexString(va) + " (" + f.getName() + ") ---");
                    println(code);
                    println("--- End C Code ---");
                }
            } else {
                println("No function found at 0x" + Long.toHexString(va));
            }
        }
        println("=== TraceIvOffsetFormula.java finished ===");
    }
}
