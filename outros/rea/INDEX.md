# Acervo de Engenharia Reversa — PS4 Baikal (Índice Geral)

> **Estrutura padrão por subsistema:**
> ```
> <subsistema>/
> ├── decompiled/     # Funções decompiladas do kernel Orbis (FreeBSD-based)
> ├── scans/          # Varreduras de hardware ao vivo (MMIO, PCI, BARs)
> ├── docs/           # Documentação de referência consolidada
> ├── harness/        # Scripts de teste ao vivo (Python, shell) — se aplicável
> ├── dumps/          # Binários de teste (.ko, dumps brutos) — se aplicável
> ├── plans/          # Planos de desenvolvimento de drivers
> └── INDEX.md        # Este arquivo por subsistema
> ```

---

## Subsistemas Organizados

| Subsistema | Dispositivo PCI | Status | Pasta |
|------------|-----------------|--------|-------|
| **SPM / Baikal Memory** | 00:14.6 (104d:90dd) | ✅ Fases 1-5 implementadas, driver `baikal-memory.ko` v0.2 | `spm/` |
| **ACPI** | 00:14.0 (104d:90d7) | 🔴 Sem driver — plano criado | `acpi/` |
| **DMA** | 00:14.5 (104d:90dc) | 🔴 Sem driver — plano criado | `dma/` |
| **Ethernet GBE** | 00:14.1 (104d:90d8) | 🟡 Driver `mts.ko` funcional (TX), **RX bloqueado (PHY)** | `ethernet/` |
| **WiFi MediaTek (MT6632/MT7668)** | SDIO (`mmc0:0001`) | 🟡 Associa e tem SSH, mas **sem NVRAM** (`load manufacture data fail`, país 00) | `wifi/` |

---

## Referência Rápida por Dispositivo

| PCI ID | Função | Dispositivo | Driver Linux | Status |
|--------|--------|-------------|--------------|--------|
| 104d:90d7 | 00:14.0 | Baikal ACPI | — | 🔴 Plano: `acpi/plans/` |
| 104d:90d8 | 00:14.1 | Baikal GBE Ethernet | `mts.ko` | 🟡 TX OK, RX PHY down |
| 104d:90dc | 00:14.5 | Baikal DMA Controller | — | 🔴 Plano: `dma/plans/` |
| 104d:90dd | 00:14.6 | Baikal Memory (SPM) | `baikal-memory.ko` | ✅ v0.2 ativo |

---

## Navegação

- `acpi/` → `acpi/INDEX.md` → `acpi/plans/PLANO_DRIVER_ACPI_BAIKAL.md`
- `dma/` → `dma/INDEX.md` → `dma/plans/PLANO_DRIVER_DMA_BAIKAL.md`
- `ethernet/` → `ethernet/INDEX.md` → `ethernet/plans/PLANO_DRIVER_ETHERNET_BAIKAL.md`
- `spm/` → `spm/HANDOFF.md` → `spm/decompiled/baikal_mem_plano_driver.md`
- `wifi/` → `wifi/INDEX.md` → `wifi/plans/PLANO_DRIVER_WIFI_BAIKAL.md`

---

## Convenções de Nomenclatura (Arquivos Decompilados)

| Padrão | Exemplo | Significado |
|--------|---------|-------------|
| `<nome_curto>_<addr>.txt` | `mtsc_pci_attach_dc5a0070.txt` | Função `dc5a0070` = `mtsc_pci_attach` |
| `<categoria>_<descritivo>.md` | `baikal_mem_fase2_orbis_strings.md` | Análise de strings da Fase 2 |
| `decompiled_<addr>.txt` | `decompiled_dc5a44c0.txt` | Extração Ghidra (`extracted/`) |
| `legacy_raiz/decompiled_<nome>.txt` | `decompiled_gbe_phy_attach.txt` | Decompilação legada (raiz antiga) |

---

## Banco de Dados SQLite

**`ps4_hardware_memory.db`** — Fonte única estruturada:
- `hardware_registers` — Catálogo de registradores (device, BAR, offset, safe_to_read/write)
- `readonly_verification` — Leituras confirmadas ao vivo (endereço, valor baseline/atual)
- `bar_regions` — Mapeamento BARs por dispositivo PCI
- `write_sweep_results` — Testes de escrita (valor antes/depois, ping/telnet sobreviveram)
- `decompiled_functions` — Catálogo funções decompiladas (addr_hex, category, role, status, validated_by_test_id)
- `test_history` — Histórico cronológico de testes ao vivo

```bash
# Exemplos de consultas
sqlite3 ps4_hardware_memory.db "SELECT * FROM decompiled_functions WHERE category='MTS';"
sqlite3 ps4_hardware_memory.db "SELECT * FROM readonly_verification WHERE device='GBE';"
```

---

## Princípios de Organização

1. **Uma pasta por subsistema hardware** (não por tipo de arquivo)
2. **Decompilado separado de scans** — RE estático vs dinâmico
3. **Planos em `plans/`** — versão viva, atualizada conforme progresso
4. **Documentação em `docs/`** — cópias de referência do `outros/docs/`
5. **Harness em `harness/`** — scripts testados ao vivo, prontos para reuso
6. **Índice `INDEX.md` em cada pasta** — entrada rápida ao acervo