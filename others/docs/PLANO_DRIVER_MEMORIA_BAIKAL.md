# Plano — Driver de Memória Baikal (00:14.6 / SPM DDR3)

**Item no BACKLOG.md:** #5 — Baikal Memory (00:14.6) — desenvolver driver de memória SPM/DDR3  
**Data:** 2026-11-12  
**Status:** Iniciando investigação  
**Prioridade:** Média (não bloqueante, estratégica de médio prazo)

---

## 1. Objetivo

Desenvolver um driver de kernel Linux (`baikal-memory.ko`) que expõe de forma segura e estruturada a memória dedicada do Southbridge Baikal (SPM/DDR3, dispositivo PCI 00:14.6), permitindo:

- Leitura/estruturada da memória compartilhada com o Syscon/EMC via `mmap` ou interface de caractere
- Suporte ao driver RTC `rtc-ps4-icc` (depende de MMIO e contexto ICC nessa região)
- Controle de power/thermal/S5 (desligamento total com luz azul apagando)
- Base para drivers futuros do Baikal (ACPI 00:14.0, DMA 00:14.5)

---

## 2. O que já sabemos (coleta ao vivo + REA)

### Dispositivo PCI 00:14.6 (Baikal Memory)
| Campo | Valor (do `lspci` ao vivo) |
|-------|---------------------------|
| Vendor | 0x104d (Sony Corporation) |
| Device | 0x90dd (Baikal Memory) |
| Classe | System peripheral (0880) |
| Driver | Nenhum |

### BARs do dispositivo 00:14.6 (PRECISAM SER VALIDADOS ao vivo)
O dump do repositório DEBARSHI-SARKAR/PS4-BAR-dump é do **Belize** (0x90ce), não Baikal (0x90dd). Endereços podem ser similares mas precisam ser revalidados:

| BAR | Endereço (Belize) | Tamanho | Propósito |
|-----|-------------------|---------|-----------|
| BAR0 | 0xd8000000–0xd8000fff | 4 KiB | MMIO do controlador de memória |
| BAR2 | 0x80000000–0xbfffffff | 1 GiB | Região DDR3/SPM principal |
| BAR4 | 0xd9100000–0xd91fffff | 1 MiB | MMIO adicional |
| BAR5 | 0xd9000000–0xd903ffff | 256 KiB | MMIO adicional |

> ⚠️ **Corrigido em 2026-11-16:** este aviso dizia que o console era um PS4 Slim com 256 MB de SPM. O console é um **PS4 Pro com Baikal**. Medido em 2026-11-16: o BAR2 anuncia 1 GiB, mas a SPM só responde (zeros) de 0 a 188 MiB e devolve `0xFF` depois, tanto pela CPU quanto pelo DMA. Uma medição antiga dava 256 MB; as duas discordam e a diferença não foi explicada.

### Conhecimento do projeto (REA)
- Nenhuma função de memória/SPM/DDR3 foi decompilada (banco vazio para esse dispositivo)
- Nenhum registro em `hardware_registers` ou `bar_regions` para 00:14.6
- O banco de REA tem apenas dispositivos: GbE, Glue, Trimming, SATA AHCI, xHCI+AHCI, GPU, IOMMU, ECAM

---

## 3. Plano de Execução (fases)

### Fase 1 — Mapeamento ao vivo (sem recompilar kernel)
**Objetivo:** Confirmar os endereços BAR reais no hardware Baikal Slim e fazer leitura segura de registros conhecidos.

| Passo | Comando | Resultado esperado |
|-------|---------|-------------------|
| 1.1 | `lspci -vv -s 00:14.6` | BARs reais do dispositivo no hardware |
| 1.2 | `lspci -s 00:14.6 -xxx` | PCI config space completo |
| 1.3 | `find /sys/bus/pci/devices/0000:00:14.6 -name 'resource*' -o -name 'resource*'` | Recursos alocados pelo kernel |
| 1.4 | `cat /proc/iomem \| grep -i baikal` | Regiões de memória alocadas |
| 1.5 | `cat /sys/class/resource/...` (se existir) | Detalhes do recurso |

### Fase 2 — Leitura segura da SPM (usuáriospace, /dev/mem)
**Objetivo:** Ler a região de memória SPM sem escrever, para identificar padrões e offsets de interesse.

| Passo | Comando | Resultado esperado |
|-------|---------|-------------------|
| 2.1 | `dd if=/dev/mem bs=1 count=64 skip=<BAR2_base> 2>/dev/null \| xxd` | Primeiros 64 bytes da SPM |
| 2.2 | `dd if=/dev/mem bs=4 count=256 skip=<offset> 2>/dev/null \| xxd` | Varredura de offsets múltiplos de 4 |
| 2.3 | Comparar leituras antes/depois de acionar power button/fan | Quais offsets mudam |

> ⚠️ **Regra do REA:** ler `/dev/mem` é relativamente seguro em regiões não críticas, mas NUNCA escrever sem saber exatamente o que é.

### Fase 3 — Engenharia reversa com Ghidra
**Objetivo:** Entender como o kernel Orbis acessa essa memória.

| Passo | Ferramenta | Alvo |
|-------|------------|------|
| 3.1 | Ghidra headless | `kmem_dump_1252.bin` (kernel Orbis 12.52) |
| 3.2 | Scripts `ghidra_scripts/` | Extrair funções que acessam `0x80xxxxxx` ou `0xd8xxxxxx` |
| 3.3 | `decompiled/` | Funções já decompiladas relacionadas a `sc` (softc), `spm`, `icc`, `sbram` |
| 3.4 | `INDEX.md` | Catálogo canônico de funções de memória |

### Fase 4 — Desenvolvimento do driver
**Objetivo:** Criar `drivers/misc/baikal-memory.c` (ou similar) no kernel 7.0.

| Componente | Descrição |
|------------|-----------|
| Kconfig | `CONFIG_BAIKAL_MEMORY` (tristate, módulo) |
| Makefile | Objeto do driver |
| Driver | Probe PCI (vendor 0x104d, device 0x90dd), ioremap BAR2+BAR0, registro de dispositivo de caractere + mmap |
| sysfs | Atributos para leitura de offsets conhecidos (somente leitura inicialmente) |

### Fase 5 — Teste ao vivo no PS4
**Objetivo:** Validar que o driver funciona sem travar o console.

| Teste | Critério de aceite |
|-------|-------------------|
| `modprobe baikal-memory` | Módulo carrega sem kernel panic |
| `/dev/baikal-memory` existe | Dispositivo de caractere criado |
| `mmap` na SPM | Leitura retorna dados não-zero e estáveis |
| `cat /sys/class/baikal-memory/...` | Atributos sysfs legíveis |
| Reboot | Console volta a bootar normalmente |

---

## 4. Riscos e Mitigações

| Risco | Mitigação |
|-------|-----------|
| Escrever na SPM corrompe o estado do Syscon | **NUNCA escrever** na Fase 1-2. Somente leitura via `/dev/mem` com `dd` |
| Ler offsets críticos travar o console | Começar com leituras pequenas (64 bytes) e ir aumentando gradualmente |
| 1 GiB não cabe no ioremap de kernel | Mapear em janelas menores (ex: 4 MiB por vez) ou mapear apenas BAR0/BAR4 inicialmente |
| Driver conflicts com `ps4-bpcie-icc` | Coordenar acessos via spinlock; o driver de memória é somente-leitura inicialmente |

---

## 5. Critério de Aceite

- [ ] BARs do 00:14.6 confirmados ao vivo no PS4 Slim
- [ ] Driver compila no kernel 7.0 Baikal
- [ ] Módulo carrega sem panic no PS4
- [ ] Leitura da SPM via driver retorna dados consistentes
- [ ] Reboot do console bem-sucedido após carregar/descarregar o módulo

---

## 6. Referências

- `others/rea/ps4_hardware_memory.db` — banco SQLite (vazio para este dispositivo, preencher conforme avançar)
- `others/rea/decompiled/` — saídas do Ghidra já existentes
- `others/rea/dumps/kmem_dump_1252.bin` — dump do kernel Orbis 12.52 para RE
- `others/docs/LEVANTAMENTO_HARDWARE_PS4_BAIKAL.md` — levantamento técnico completo
- `others/rea/scans/` — varreduras de MMIO já feitas
- Repositório DEBARSHI-SARKAR/PS4-BAR-dump — BAR maps de referência (Belize/Aeolia)
- `kernel/drivers_mts/` — driver MTS como exemplo de driver Baikal escrito do zero
