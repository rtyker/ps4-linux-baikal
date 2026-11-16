# Baikal DMAC — strings do Orbis (kmem_dump_1252.bin)

**Fonte:** `strings -t x others/rea/dumps/kmem_dump_1252.bin` (offsets de arquivo, não endereços virtuais; o mapeamento para endereço do Orbis não foi determinado). Nenhum registrador foi lido no PS4.

## O que é o controlador (evidência direta)

| Item | Evidência (offset no dump) |
|---|---|
| Driver Baikal | `baikal_dmac_pci` (0x805e57), `pci/baikal_dmac`, `Baikal DMA1 controller` (0x805e80), `Baikal DMA2 controller` (0x805e97) |
| Arquivo-fonte Baikal | `...\sys\dev\scesb\dmac\dmac_mtk.c` (0x805f87). O sufixo **`mtk`** sugere IP MediaTek |
| Arquivo-fonte Aeolia (outro chip) | `dmac_mvl.c` (0x7a74d5), sufixo `mvl` sugere Marvell. Registradores diferentes dos do Baikal |
| Natureza | **DMA por descritores**: strings `Can't create DMA desc tag`, `DMA_DESCRIPTOR_BASE`, `[%02d] bcount / src / dst / next`, `nseg too large`, `invalid align: src, dst, size` |
| Interrupção | `dmac_interrupt` (0x805fdf), `dmac_callback` (0x80615b), `dma error detect 0x%X` |

## Registradores citados no dump de debug do Baikal (nomes; **offsets desconhecidos**)

`DMA_INT_FLAG`, `DMA_INT`, `DMA_EN`, `DMA_RST`, `DMA_DESC_ADDR`, `DMA_CON`, `DMA_SRC_ADDR`, `DMA_DST_ADDR`, `DMA_LEN`, `DMA_DESC_EN`, `DMA_DEBUG_ST` (0x805fee–0x8060d4).

Descritor (por entrada): `bcount`, `src`, `dst`, `next`.

## Quem usa o DMAC no Orbis

- `aeolia_dmac_xfer_upstream` / `aeolia_dmac_xfer_downstream` (nome herdado do Aeolia; usado também no Baikal). Aparece no caminho de swap de memória em HDD (`HDD for DMEM swap is not open`, `aes128_xts failed`, `hmac_sha256 failed`, `sceSblDriverUnmapPages`) e em `bd_sched_hdd_writer_write_hdd` (`aeolia_dmac_xfer_upstream() failed`).
- `src/system/mt_dmac.c` (0xacb4a0): camada acima do driver.
- `diag_dmac_xfer_upstream` / `diag_dmac_xfer_downstream` (0xb210ed, 0xb21128): interface de diagnóstico com `copyin`/`copyout`.

## O que isto implica (e o que não)

- **Não é um 8237 legado.** A hipótese anterior (offsets `0x00/0x80/0xC0` do mapa AT) está **descartada como explicação do controlador**: os nomes e a estrutura são de um DMA de descritores. Os offsets do `hardware_report.txt` continuam sem validação.
- **Hipótese não verificada:** o `upstream`/`downstream` move dados entre a RAM do host e o lado da southbridge (possivelmente a SPM/DDR3 de 256 MiB que o `baikal-memory` já expõe por PIO). Isso é uma leitura dos nomes, sem decompilação.
- **Semelhança de nomes** com o mainline: `drivers/dma/mediatek/mtk-cqdma.c` (`INT_FLAG`, `INT_EN`, `EN`, `RESET`, `SRC`, `DST`, `LEN1`). **Só serve como pista de estudo**; os offsets do Baikal não são os do CQDMA por inferência.

## Próximo passo de RE (host, sem risco)

Descobrir os offsets reais decompilando o `dmac_mtk.c`: a função que imprime o dump de registradores (strings 0x805fee–0x8060d4) tem as leituras com os offsets, e `dmac_interrupt`/`dmac_callback` mostram o fluxo. Falta mapear offset de arquivo → endereço virtual (base do dump) para usar o Ghidra.
