// Teste minimal: ghidra script java
//@category PS4-MTS

import ghidra.app.script.GhidraScript;

public class ExtractMtsNamespaceTest extends GhidraScript {
    @Override
    public void run() throws Exception {
        println("OK script Java carregou");
        println("Program: " + currentProgram.getName());
    }
}
