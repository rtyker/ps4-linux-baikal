# baikal_dmac_test — harness de RE do DMAC Baikal (00:14.5)

Módulo de kernel **externo** para validar o hardware, com buffers próprios (`dma_alloc_coherent`). Não é o driver: o driver `dmaengine` é `drivers/dma/baikal-dmac.c` (patch `kernel/patches/baikal-dmac.patch`). Mapa de registradores e resultados: `../../decompiled/baikal_dmac_mtk_registers_20261113.md`.

**Os dois disputam o mesmo dispositivo PCI (`104d:90dc`).** Descarregue o `baikal-dmac` (`rmmod baikal_dmac`) antes de carregar este.

## Build (host)

```bash
cd /mnt/hdauxiliar/ps4-linux-baikal
sudo make -C kernel/kernel_build_7.0 M=$PWD/outros/rea/dma/harness/baikal_dmac_test \
     ARCH=x86_64 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm modules
sudo chown -R $USER:$USER outros/rea/dma/harness/baikal_dmac_test
objcopy --remove-section=.BTF --remove-section=.BTF.base \
     outros/rea/dma/harness/baikal_dmac_test/baikal_dmac_test.ko   # mesmo truque do mts.ko
```

O `vermagic` precisa bater com o kernel do PS4 (`modinfo -F vermagic`).

## Uso (PS4)

```bash
scp baikal_dmac_test.ko root@192.168.6.128:/tmp/
insmod /tmp/baikal_dmac_test.ko run=0 bar=0                    # só lê e imprime os registradores
insmod /tmp/baikal_dmac_test.ko run=1 bar=0 tests=15           # suíte completa por polling
insmod /tmp/baikal_dmac_test.ko run=1 bar=0 tests=3 irqmode=1  # com interrupção MSI (BAR0)
rmmod baikal_dmac_test
```

Parâmetros: `run`, `bar` (0 ou 2), `tests` (máscara: 1 simples, 2 encadeamento, 4 grande, 8 alinhamentos), `bigkb` (tamanho do teste grande, 4–1024 KiB), `inten`, `irqmode`, `nvec`.

## Salvaguardas

Só opera com o controlador ocioso; zera `LEN`/`SRC`/`DST` e confere a releitura antes de armar; usa só buffers próprios com 4 KiB de guarda conferida byte a byte; se uma transferência não concluir, **não libera** os buffers (o DMA nunca escreve em memória reaproveitada).

## Achados que ficaram aqui

- BAR0 (DMAC1?) entrega MSI; **BAR2 (DMAC2?) não entrega**: investigação pendente no `BACKLOG.md`.
- Para liberar MSI no teardown use `pci_free_irq_vectors(pdev)`; o `bpcie_free_irqs()` deixou entradas e gerou `WARNING` em `msi_device_data_release`.
