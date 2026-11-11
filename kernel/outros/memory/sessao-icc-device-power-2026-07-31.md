# Sessão 2026-07-31 — Análise ICC device_power (major=5) via PyGhidra

## Objetivo
Decompilar as funções ICC device_power (major=5) para confirmar se GBE PHY power-on está nesse domínio.

## O que foi feito

### 1. Extração via PyGhidra headless (Docker) ✅
- Container: `ghidra-py` (Ghidra + PyGhidra)
- Script: `ExtractMtsNamespacePyGhidra.py` (corrigido para API Ghidra 12.1.2)
- 26 endereços-alvo (19 já existentes + 7 novos ICC device_power)
- **Todos 26 extraídos com sucesso** (7 novos, 19 skipped)

### 2. Funções ICC device_power extraídas e analisadas

| Função | Endereço | Papel | Status |
|--------|----------|-------|--------|
| `icc_device_power_main` | `dc7c8b80` | Dispatcher ICC major=5. Chama get(0x31)/set(0x30) para device types 0,1. **GBE não está na lista.** | ✅ revisado |
| `icc_devpower_get` | `dc7c8fb0` | Lê estado de power via ICC major=5, minor=0x31 (GET) | ✅ revisado |
| `icc_devpower_set` (B) | `dc7c8a70` | Escreve estado via ICC major=5, minor=0x30 (SET) | ✅ revisado |
| `icc_devpower_set` wrapper | `dc7c8a30` | Chama `dc7c8a70` com minor=0, value=param_1 | ✅ revisado |
| `icc_power` dispatcher | `dc528600` | Registra 5 handlers + GBE handler `dc528ef0` (4/0x38). Envia query ICC major=4 minor=4 | ✅ revisado |
| `icc_power_set` alias | `dc478a70` | Decompilação falhou (bad instruction data) | ⚠️ bruto |
| Clone device_power_main | `dc478b80` | Lógica complexa de power para múltiplos devices | ✅ revisado |

### 3. Conclusão crítica
**GBE NÃO está no ICC device_power (major=5).** O dispatcher só trata device types 0 e 1 (wlan, bt, usb, hdd, bd, etc.). O PHY GBE é ligado pelo firmware/bootloader Sony ANTES do kernel Orbis assumir — não há comando ICC/SAMU replicável para ligar o PHY.

O ICC 4/0x38 (handler `dc528ef0`) só liga o **MAC core** (confirmado: `BAR0+0x004` muda de 0 para 0xb19). O PHY permanece mudo.

### 4. SQLite atualizado
- 7 funções marcadas como `revisado` em `decompiled_functions`
- Entrada em `test_history` para esta sessão

### 5. Documentação atualizada
- `consolidado/decompiled/INDEX.md`: Nova seção 4.B "ICC device_power (major=5)"
- `PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md`: Já reflete conclusão final (Passo 1+2 concluídos, via esgotada)

## Artefatos criados
- `consolidado/decompiled/extracted/decompiled_dc7c8b80.txt` (133 linhas)
- `consolidado/decompiled/extracted/decompiled_dc7c8fb0.txt` (38 linhas)
- `consolidado/decompiled/extracted/decompiled_dc7c8a70.txt` (28 linhas)
- `consolidado/decompiled/extracted/decompiled_dc7c8a30.txt` (26 linhas)
- `consolidado/decompiled/extracted/decompiled_dc528600.txt` (42 linhas)
- `consolidado/decompiled/extracted/decompiled_dc478a70.txt` (44 linhas - bruto)
- `consolidado/decompiled/extracted/decompiled_dc478b80.txt` (173 linhas)

## Próximos passos viáveis (para GBE)
A via ICC/SAMU/RMU/MDIO para PHY power-on está **esgotada com os dados atuais**. Opções restantes:
1. **Capturar Orbis quiesce no reboot** (UART log do desligamento Orbis antes do kexec) — verificar se desliga PHY
2. **Investigar domínio de power do PHY via hardware** (oscilloscópio no rail Syscon GBE) — requer acesso físico
3. **Buscar nova fonte de dados** (vazamento firmware Sony, dump SAMU, documentação técnica Baikal PHY)

## Limpeza
- Removido `.class` artifact
- Script Java restaurado