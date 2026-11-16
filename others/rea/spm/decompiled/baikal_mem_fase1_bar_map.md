# Achados Fase 1 — Mapeamento de Memória Baikal (00:14.6)

**Data:** 2026-11-12  
**Dispositivo:** Sony Baikal Memory (DDR3/SPM), PCI 00:14.6, Vendor 0x104d, Device 0x90dd  
**Hardware:** PS4 Slim (CUH-2xxx, Baikal B1), 256 MB SPM DDR3  
**Status:** Fase 1 concluída — mapeamento ao vivo finalizado

---

## 1. BARs Confirmados ao Vivo

| BAR | Endereço Físico | Tamanho | Tipo | Conteúdo |
|-----|-----------------|---------|------|----------|
| BAR0 | 0xcc000000–0xcc000fff | 4 KiB | MMIO (64-bit, non-prefetchable) | **Todo 0xFF** — não mapeado/inicializado |
| BAR2 | 0x80000000–0xbfffffff | 1 GiB | Memória (64-bit, non-prefetchable) | Zeros até 256 MB, depois 0xFF (256 MB real) |
| BAR4 | 0xcd000000–0xcd0fffff | 1 MiB | MMIO (32-bit, non-prefetchable) | **Todo 0x00** — vazio |
| BAR5 | 0xcd400000–0xcd43ffff | 256 KiB | MMIO (32-bit, non-prefetchable) | **Tabela estruturada** com dados |

> **Nota:** O PS4 Slim tem 256 MB de SPM DDR3 (1 chip 2Gb), não 1 GB como o Pro. Confirmado pelo padrão zeros→0xFF no BAR2.

---

## 2. BAR5 (0xcd400000, 256 KiB) — Tabela Estruturada

O BAR5 contém dados em quase toda sua extensão. Estrutura observada:

### Offset 0x0000–0x0190: Cabeçalho + entradas variadas
```
0000: 2109 0002 0000 0100 1208 0100 0000 0081
0010: 8805 0108 1208 0100 1208 0100 0000 0081
0020: 8905 0100 1208 0100 bf07 0808 0000 0081
0030: f205 0818 bf07 0808 210a 0000 0100 0000
...
```
Padrões repetidos: `1208 0100`, `bf07 0808`, `5f0d 0808`, `8805 0810`, `da9b 000c`, `8413 0004`, `d49b 000c`, `8c13 0004`, `9013 0004`, `9413 0004`, `9813 0004`, `9c13 0004`, `a013 0004`, `a413 0004`, `a813 0004`

### Offset 0x01a0–0x0750: Blocos repetidos `da9b/d49b` + `8413/8813/8c13/9013/9413/9813/9c13/a013/a413/a813` + `0004 0001`

### Offset 0x0760 onwards: Blocos de `8013 0d00 0000 0082` repetidos

### Offset ~0x1fe0–0x1fff: Dados diferentes (não-zero, não-repetitivo)

### Propriedades observadas:
- **Estático:** Não muda entre leituras separadas por 2 segundos
- **Padrões repetitivos:** Sugere tabela de descritores, comandos ICC, ou registradores de controle de memória
- **Não-zero:** Ao contrário do BAR4 (todo zero) e BAR2 (zeros na maior parte)

---

## 3. BAR0 (0xcc000000, 4 KiB) — Todo 0xFF

Toda a região de 4 KiB retorna 0xFF. Isso indica que:
- O registro não está mapeado para memória física real, ou
- O dispositivo precisa de alguma inicialização para expor dados neste BAR, ou
- É um registro write-only (leituras retornam 0xFF por design)

---

## 4. BAR2 (SPM DDR3, 1 GiB endereçado)

| Faixa | Conteúdo | Interpretação |
|-------|----------|---------------|
| 0x00000000–0x0FFFFFFF (256 MB) | 0x00 | Memória DDR3 presente, inicializada com zeros |
| 0x10000000–0xBFFFFFFF (768 MB) | 0xFF | Memória não fisicamente presente (Slim tem 256 MB) |

> Conforme PS4 Developer Wiki: "PS4 Fat and Slim Southbridge has access to one 2Gb DDR3 chip, for a total of 256MB of memory."

---

## 5. Strings Encontradas no Kernel Orbis (kmem_dump_1252.bin)

Strings críticas relacionadas à memória Baikal encontradas via `strings` no dump:

| String | Contexto |
|--------|----------|
| `Baikal Scratch Pad Memory` | Nome do dispositivo no kernel Orbis |
| `spm_pci` | Nome do driver/PCI |
| `pci/spm` | Caminho PCI do dispositivo |
| `failed to call bootparam_get_ddr3_capacity` | Erro ao obter capacidade DDR3 |
| `invalid ddr3_size %#x` | Tamanho DDR3 inválido |
| `failed to create thread for ddr3swap: ret=%#x` | Thread ddr3swap |
| `[DDR3SWAP DEBUG] ...` | Logs de debug do ddr3swap |
| `ddr3swap_state` | Estado do ddr3swap |
| `ddr3swap_hdd.lock_hdd` | Lock do HDD no ddr3swap |
| `ddr3swap:mtx` / `ddr3swap:cv` | Mutex e cond var do ddr3swap |
| `SceDdr3Swap` | Módulo do sistema Orbis para swap DDR3 |
| `ddr3swap_crypt:mtx` | Mutex de criptografia do ddr3swap |

> Interpretação: O kernel Orbis tem um driver `spm_pci` para a Scratch Pad Memory e um subsistema `SceDdr3Swap` que usa a DDR3 do southbridge como swap criptografado. Isso confirma que a memória Baikal (00:14.6) é ativamente usada pelo sistema Orbis.

---

## 6. Arquivos Salvos

| Arquivo | Conteúdo | Tamanho |
|---------|----------|---------|
| `/tmp/baikal_bar5.bin` | BAR5 completo (256 KiB) | 262144 bytes |
| `/tmp/baikal_bar0_correto.bin` | BAR0 completo (4 KiB) | 4096 bytes |

---

## 7. Próximos Passos (Fase 2)

1. **Analisar a estrutura do BAR5** — identificar campos, tamanhos de entrada, significado dos padrões repetidos
2. **Comparar com decompilações existentes** no REA (funções ICC, `icc_query`, `icc_device_power`)
3. **Ler com offsets diferentes** para encontrar registradores de estado (power, thermal, fan)
4. **Verificar se leituras mudam** após acionar power button ou fan (teste de atividade)
5. **Começar RE com Ghidra** no `kmem_dump_1252.bin` procurando funções que acessam `0xcd4xxxxx` ou `0x80xxxxxx`
6. **Desenvolver driver** `baikal-memory.ko` para o kernel 7.0 Baikal

---

## 8. Referências

- `others/rea/ps4_hardware_memory.db` — banco SQLite (vazio para este dispositivo)
- `others/rea/dumps/kmem_dump_1252.bin` — dump do kernel Orbis 12.52
- `others/rea/decompiled/` — saídas do Ghidra
- `others/rea/scans/` — varreduras de MMIO
- DEBARSHI-SARKAR/PS4-BAR-dump — BAR maps de referência (Belize/Aeolia)
- `kernel/drivers_mts/` — driver MTS como exemplo de driver Baikal escrito do zero
