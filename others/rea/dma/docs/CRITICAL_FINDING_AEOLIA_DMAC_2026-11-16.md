# DESCOBERTA CRÍTICA: DDR3 Swap usa Aeolia DMAC (00:14.7), NÃO DMAC Standalone (00:14.5)

**Data:** 2026-11-16  
**Análise:** Raw dump inspection + string search no `kmem_dump_1252.bin`  
**Impacto:** **Muda completamente o alvo do plano** — testar DMAC errado até agora

---

## Resumo Executivo

O writeup do Debarshi cita "southbridge DMA engine" PCI `104d:90cd` para Belize (PS4 Pro). Assumimos que o equivalente no Baikal Slim seria o DMAC standalone `104d:90dc` em `00:14.5`.

**ERRADO.** O kernel Orbis usa o **Aeolia DMAC** (integrado no device composto xHCI+AHCI `00:14.7`) para o DDR3 swap, via função `aeolia_dmac_xfer_upstream()`.

---

## Evidências do Dump Orbis

### 1. Strings do DDR3 Swap (região 0x7ea800+)
```
ddr3swap_state
init_swap / init dmem swap
prepare_swap / prepare dmem swap
ddr3swap:mtx / ddr3swap:cv
ddr3swap_crypt:mtx / ddr3swap_crypt:cv
SceDdr3Swap (thread name)
failed to create thread for ddr3swap
ddr3swap_hdd.lock_hdd
```

### 2. Chamada de DMA no Writer Thread
String em `0xae2eac`: `"aeolia_dmac_xfer_upstream() failed. %d"`
- Função chamada de `bd_sched_hdd_writer_write_hdd`
- Writer thread do DDR3 swap chama Aeolia DMAC para mover dados upstream

### 3. Device Strings do Aeolia DMAC (região 0x7a7373+)
```
aeolia_dmac_pci
pci/aeolia_dmac
pci/dmac
Aeolia DMA1 controller
Aeolia DMA2 controller
Belize DMA1 controller
Belize DMA2 controller
```

**Confirma:** Aeolia tem **DOIS controladores DMA** (DMA1, DMA2), igual ao DMAC standalone.

### 4. PCI Device Match Function (0x471090+)
Código em `0xffffffffdc7c1090` faz match de vendor/device IDs:
```asm
cmp edx, 0x104d        ; vendor Sony
je check_devices
cmp edx, 0x90dd        ; SPM (00:14.6) -> je handler_SPM
cmp edx, 0x90ce        ; Device ? -> je handler_1
cmp edx, 0x90a3        ; Device ? -> je handler_2
```

### 5. Device IDs Conhecidos
| Device | Função | PCI Location | Device ID |
|--------|--------|--------------|-----------|
| SPM/DDR3 | Memória | 00:14.6 | 0x90dd |
| GBE Ethernet | Rede | 00:14.1 | 0x90d8 |
| SATA AHCI genérico | Disco | 00:14.2 | ? |
| Glue Logic | Clock/Reset | 00:14.4 | ? |
| **Aeolia (xHCI+AHCI)** | **USB + SATA real + DMA** | **00:14.7** | **0x90ce ou 0x90a3** |
| DMAC Standalone | Memcpy | 00:14.5 | 0x90dc |

### 6. bar_regions Confirma Aeolia em 00:14.7
```
8|Baikal xHCI+AHCI composto (Aeolia)|0000:00:14.7|BAR2|0xce800000|64KB|Device REAL do disco interno (ata1)... Driver xhci_aeolia tem seu PROPRIO ahci_init_one()... Confirmado ao vivo 2026-08-01
```

---

## Mapeamento Correto

| Writeup (Belize) | Baikal Slim (Realidade) |
|------------------|-------------------------|
| PCI `104d:90cd` "southbridge DMA engine" | **Aeolia DMAC** em `00:14.7` (device ID 0x90ce ou 0x90a3) |
| Registrador GO `0x1d40` | Desconhecido — Aeolia DMAC tem registradores próprios |
| Buffer de staging < 4GB | Provavelmente mesmo mecanismo |
| 504 MB/s read, 425 MB/s write | Meta para testar no Aeolia DMAC |

---

## O Que Testamos Até Agora (ERRADO)

| Componente | Device | Status |
|------------|--------|--------|
| DMAC Standalone (nosso harness) | 00:14.5 (104d:90dc) | ✅ Funciona para memcpy host↔host (~900 MB/s) |
| **Aeolia DMAC (DDR3 swap real)** | **00:14.7 (104d:90ce/90a3)** | **NUNCA TESTADO** |

---

## Próximos Passos Corrigidos

### Imediato (sem PS4)
1. Identificar qual device ID (0x90ce ou 0x90a3) é o Aeolia DMAC
2. Encontrar registradores do Aeolia DMAC (BARs do device 00:14.7)
3. Extrair função `aeolia_dmac_xfer_upstream` via Ghidra

### No PS4 (Passo 1-4 revisados)
1. **Baseline CPU** do `baikal-memory` (inalterado)
2. **Testar Aeolia DMAC lendo SPM BAR2** — device 00:14.7, controladores DMA1/DMA2
3. **Comparar performance** com DMAC standalone
4. **Decisão:** Se Aeolia DMAC acessa SPM BAR2 → integração no `baikal-memory` via Aeolia

---

## Arquivos Afetados

| Arquivo | Ação |
|---------|------|
| `PLANO_DMA_SPM_DDR3_2026-11-16.md` | **REESCREVER** — alvo muda de 00:14.5 para 00:14.7 |
| `baikal_dmac_test_spm.c` | **DESCARTAR** — testava DMAC errado |
| Novo harness | Criar para Aeolia DMAC (00:14.7) |
| `kernel/patches/baikal-dmac.patch` | Revisar — driver dmaengine atual é para 00:14.5 |

---

## Comandos para Investigar Aeolia DMAC

```bash
# 1. Ver device IDs no PCI match
sqlite3 others/rea/ps4_hardware_memory.db "SELECT * FROM bar_regions WHERE device LIKE '%Aeolia%';"

# 2. Buscar registradores Aeolia no dump
# Ghidra headless nos endereços da função aeolia_dmac_xfer_upstream

# 3. No PS4: lspci -nn | grep 104d
# Deve mostrar 00:14.7 com device ID 90ce ou 90a3
```

---

## Conclusão

**O plano original testava o hardware errado.** O DDR3 swap do Orbis usa o **Aeolia DMAC (00:14.7)**, que é parte do controlador xHCI+AHCI composto, não o DMAC standalone (00:14.5).

Isso explica:
- Por que o writeup cita device ID `104d:90cd` (Belize) — no Baikal o equivalente é o Aeolia
- Por que o registrador GO `0x1d40` não existe no nosso DMAC — é registrador do Aeolia
- Por que o DMAC standalone funciona para memcpy mas **nunca foi testado com SPM** — o Orbis não o usa para SPM

**Ação:** Pivotar o plano para testar o **Aeolia DMAC**.