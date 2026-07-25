# Teste simples PyGhidra
print("OK Python carregou")
print("Program:", currentProgram.getName() if currentProgram else "NONE")
fm = currentProgram.getFunctionManager()
funcs = list(fm.getFunctions(True))
print(f"Total functions: {len(funcs)}")
# Função na primeira posição 0xffffffffdc5a0070?
target = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(0xffffffffdc5a0070)
print(f"Memory contains 0xdc5a0070: {currentProgram.getMemory().contains(target)}")
f = fm.getFunctionAt(target)
print(f"Function at 0xdc5a0070: {f}")
