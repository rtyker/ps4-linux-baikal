# Baikal DMA (00:14.5) — Índice do Acervo

## Estrutura
```
dma/
├── decompiled/          # Funções decompiladas do kernel Orbis
│   ├── baikal_mem_fase2_orbis_strings.md   # Strings: "Baikal DMA1/2 controller", "baikal_dmac_pci"
│   ├── baikal_mem_plano_driver.md          # Menção a driver DMA
│   └── res_alloc_helper_dc5ba5e0.txt       # Helper alocação recursos
├── scans/               # Varreduras de hardware
│   ├── hardware_report.txt                 # MMIO ca000000/ca800000 (as faixas de "DMA Channel/Page" nele são portas do DMA legado do PC, anotadas como erro)
│   └── kernel_hardware_info.txt
├── docs/                # Documentação de referência
│   ├── LEVANTAMENTO_HARDWARE_PS4_BAIKAL.md
│   ├── STATUS_DRIVERS_PS4_BAIKAL.md
│   └── ACHADOS_MEMORIA_BAIKAL_FASE2.md
└── plans/
    └── PLANO_DRIVER_DMA_BAIKAL.md          # Plano de desenvolvimento
```

## Dispositivo
- **PCI:** 104d:90dc (00:14.5)
- **BAR0:** 0xCA000000 (4 KiB, medido ao vivo 2026-11-13)
- **BAR2:** 0xCA800000 (4 KiB, medido ao vivo 2026-11-13)
- **BAR1:** não existe.
- Os papéis dos blocos (canal 1, canal 2, page regs) e seus offsets vêm de fontes antigas e **não foram validados**. Ver `plans/PLANO_DRIVER_DMA_BAIKAL.md`.
- **IRQ:** Via BPcie function 5 (DMAC) — demux já implementado

## Resultado do teste de escrita (2026-11-13)
**O DMAC executa transferências por descritor, nos dois BARs.** Memcpy de 256 bytes validado com o harness `harness/baikal_dmac_test/`. Mapa e sequência em `decompiled/baikal_dmac_mtk_registers_20261113.md`. Falta: encadeamento, tamanhos maiores, interrupção e o driver `dmaengine`.

## Status (revisado 2026-11-13)
Plano revisado: os BARs medidos são BAR0 (`ca000000`) e BAR2 (`ca800000`), sem BAR1. Não encontrei no código do Baikal uma configuração de glue para o DMAC equivalente à do Aeolia (`ps4-apcie.c:500–503`), mas a busca foi limitada a `ps4-bpcie.c` e `ps4-apcie.c`, então isso não está confirmado. O demux de IRQ do DMAC já existe (`ps4-bpcie.c:110`). O próximo passo é RE da glue no Orbis, antes de qualquer escrita. Ver `plans/PLANO_DRIVER_DMA_BAIKAL.md`.
