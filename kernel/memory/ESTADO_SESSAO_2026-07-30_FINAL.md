# Estado da Sessão — 2026-07-30 (Final)

## Objetivo
Investigar por que o PHY da GBE Baikal não liga no Linux (kexec), apesar do MAC funcionar e DMA TX completar.

## O que foi feito nesta sessão

### Passo 1 — RE de `gbe_phy_ctrl` (`dc5a44c0`) via Ghidra Java headless ✅
- **11 funções extraídas** e analisadas (tabela abaixo)
- Script Java: `consolidado/tools/ghidra_scripts/ExtractMtsNamespaceNoAnalysis.java`
- Container: `ghidra-py:latest` (Docker, idempotente)
- `.class` artifact removido

| Função | Papel | ICC/SAMU? |
|--------|-------|-----------|
| `dc5a44c0` | `gbe_phy_ctrl` — thread monitora PHY via MDIO packed reads | Não |
| `dc5a2680` | `mts_phy_mdio_read_packed` — leitura MDIO endereço `0xa2001e` | Não |
| `dc524770` | `print_debug` — genérico | Não |
| `dc6c8300` | `mutex_lock` — genérico | Não |
| `dc6c85b0` | `mutex_unlock` — genérico | Não |
| `dc48fe00` | `wait_event_timeout` — genérico | Não |
| `dcabbf00`/`dcabbe70` | `spinlock_debug` — genérico | Não |
| `dc460780` | `panic_printk` — genérico | Não |
| `dc524510` | `kernel_thread_exit` — genérico | Não |
| `dc524a80` | `small_wrapper_fn` — genérico | Não |

### Passo 2 — Cross-ref SAMU no dump Orbis ✅
- Cross-refs para `dc5a44c0`: **0** (thread criada via `kthread_create`)
- ICC major=5 (SAMU) no range GBE: **0 referências**
- MMIO SAMU no range GBE: **0 referências**
- **Conclusão:** PHY power-on é pré-kernel (firmware/bootloader Sony)

### SQLite atualizado
- 11 funções inseridas/atualizadas em `decompiled_functions` (status `revisado`)
- Entrada em `test_history` para esta sessão

### Documentação atualizada
- `PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md`: Passos 1+2 marcados ✅, Passo 3 pulado, Passo 4 = conclusão final
- `consolidado/decompiled/INDEX.md`: Nova seção "Árvore de chamada da thread gbe_phy_ctrl"
- `memory/sessao-ghidra-java-passo1-2026-07-30.md`: Memória completa da sessão

## Hipóteses já testadas e REFUTADAS

| Hipótese | Teste | Resultado |
|----------|-------|-----------|
| GBE block em reset no glue | `0x142020`, `0x180020`, `0x180074` (7+ boots) | **Não** — bits 0/4 limpos, hold=0 |
| Syscon rail via devmem | Syscon = chip `A06-COL2`, só ICC SPI | **N/A** — sem MMIO |
| ICC major=5 device_power | Todos minors testados (wlan/bt/usb/hdd/bd) | **NAK** — GBE não está lá |
| Clock config `0xc890a030` (M3) | `devmem2` write `0x16d9` | **Falhou** — registrador self-clearing, volta a 0, ChipID continua `00 00` |
| RMU PHY power-up | RE completa `gbe_phy_ctrl`: zero RMU | **Não existe** |

## O que NÃO foi testado (próximos passos viáveis)

| # | Ideia | Risco | Como testar |
|---|-------|-------|-------------|
| 1 | **Sequência completa Orbis**: clock → ICC 4 0x38 GET → MAC enable → RMU handshake → MDIO | Baixo (SSH) | Script em userspace replicando attach+up |
| 2 | **`icc_device_power` major=5 real** — decompilar `icc_device_power_main` / `icc_devpower_set` / `icc_devpower_get` para achar minor/payload GBE | Baixo (Ghidra) | Extrair funções pendentes no SQLite |
| 3 | **Capturar Orbis quiesce no reboot** — UART log do desligamento Orbis antes do kexec | Médio (precisa reboot, ~3 min) | `uart_start.sh` → `reboot -f` → `uart_stop.sh` |
| 4 | Verificar se Orbis desliga PHY no quiesce via logs já existentes | Zero (grep) | Já iniciado, logs começam pós-payload |

## Estado do hardware (baseline atual)
- **Tag**: `20260730-sata-polling-fase-ab` — melhor versão até agora
- **SATA**: Funcional (`ata1.00: configured for UDMA/100`, `dd`/`fdisk` OK)
- **GBE MAC**: Liga (`BAR0+0x004=0xb19`), DMA TX OK (RMU frames)
- **GBE PHY**: **Mudo** — MDIO Clause 22 timeout, Clause 45 retorna `0x0000`, link down
- **WiFi/SSH**: Funcional (`192.168.6.128`)

## Artefatos criados/modificados
- `consolidado/tools/ghidra_scripts/ExtractMtsNamespaceNoAnalysis.java` (novo)
- `consolidado/decompiled/extracted/decompiled_dc{5a44c0,524770,6c8300,6c85b0,48fe00,abbf00,abbe70,460780,5a2680,524510,524a80}.txt`
- `consolidado/ps4_hardware_memory.db` (SQLite atualizado)
- `PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md`, `consolidado/decompiled/INDEX.md`, `memory/sessao-ghidra-java-passo1-2026-07-30.md`

---

**Próxima sessão sugerida**: Testar sequência completa Orbis (ideia #1) via script SSH, ou decompilar `icc_device_power` (ideia #2).