# Sessão — Passo 1/2 do PLANO_GBE: RE de gbe_phy_ctrl via Ghidra Java

## O que foi feito

1. **Plano lido:** `PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md` — Passo 1 (RE de `gbe_phy_ctrl`/`dc5a44c0`) e Passo 2 (cross-ref SAMU)

2. **SQLite consultado:** `dc5a44c0` já como "revisado" mas a árvore de chamadas (~12 funções) não estava decompilada

3. **Decompilação legada lida:** `legacy_raiz/decompiled_gbe_phy_attach.txt` — confirmadas as funções chamadas

4. **Script Ghidra convertido para Java:** `consolidado/tools/ghidra_scripts/ExtractMtsNamespaceNoAnalysis.java`
   - Idêntico funcionalmente ao original Python

5. **Container Docker construído:** `ghidra-py:latest` (base: `blacktop/ghidra` + build-essential + pyghidra)

## Bloqueio resolvido
PyGhidra não carregava no headless. Solução: script Java compilado manualmente + `.class` referenciado no `-postScript`.

## Extração (✅ 11/11 funções)

| Função | Tamanho | Papel |
|--------|---------|-------|
| `dc5a44c0` | 257 inst | `gbe_phy_ctrl` — thread PHY. MDIO reads packed addr `0xa2001e`. Poll bit15 e bit2. |
| `dc524770` | 191 inst | `print_debug` — logging. Genérico. |
| `dc6c8300` | 77 inst | `mutex_lock_intr` — Genérico. |
| `dc6c85b0` | 96 inst | `mutex_unlock_intr` — Genérico. |
| `dc48fe00` | 111 inst | `wait_event_timeout` — Genérico. |
| `dcabbf00` | 119 inst | `spinlock_debug_lock` — Genérico. |
| `dcabbe70` | 81 inst | `spinlock_debug_unlock` — Genérico. |
| `dc460780` | 116 inst | `panic_printk` — Genérico. |
| `dc5a2680` | 89 inst | `mts_phy_mdio_read_packed` — leitura MDIO via packed addr `0xa2001e`. |
| `dc524510` | 115 inst | `kernel_thread_exit` — Genérico. |
| `dc524a80` | 22 inst | `small_wrapper_fn` — não SAMU. |

## Passo 2 — Cross-ref SAMU (✅ concluído)
- Cross-refs para `dc5a44c0`: **0** (thread criada via kthread_create)
- ICC major=5 (SAMU) no range GBE: **0 referências**
- MMIO SAMU no range GBE: **0 referências**
- **Conclusão:** GBE/PHY não usa SAMU nem ICC. PHY power-on é pré-kernel (firmware/bootloader Sony).

## SQLite
- 9 funções novas registradas como `revisado` em `decompiled_functions`
- Atualizada `dc5a44c0` e `dc5a2680` com papéis consolidados
- `test_history` com entrada da sessão

## Conclusão Final (Passo 4)
O PHY da GBE Baikal é ligado pelo firmware/bootloader Sony ANTES do kernel Orbis assumir. Não há
sequência replicável via MDIO, ICC, SAMU ou RMU. **Esta via de investigação está esgotada.**
Fechar formalmente em `consolidado/BACKLOG.md`.

## Artefatos criados/modificados
- `consolidado/tools/ghidra_scripts/ExtractMtsNamespaceNoAnalysis.java` (novo)
- `consolidado/decompiled/extracted/decompiled_dc{5a44c0,524770,6c8300,6c85b0,48fe00,abbf00,abbe70,460780,5a2680,524510,524a80}.txt`
- `consolidado/decompiled/INDEX.md` (atualizado)
- `PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md` (atualizado)
- `consolidado/ps4_hardware_memory.db` (SQLite atualizado)
