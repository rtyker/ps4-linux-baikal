# Plano — Baikal DMA Controller (`00:14.5`, revisado 2026-11-13)

> **Dispositivo:** Sony Baikal DMA Controller · **PCI:** `104d:90dc` (`00:14.5`) · **Subsystem:** `104d:90df`
> **Objetivo:** driver `dmaengine` (`baikal-dma`) para memcpy, com canais DMAC1/DMAC2.
> **Status:** o plano original foi **revisado** após medição ao vivo. Os BARs e a premissa de registradores estavam errados.

---

## 1. Evidência ao vivo (2026-11-13, leitura somente)

| Item | Medido | Fonte |
|---|---|---|
| BAR0 | `ca000000`, 4 KiB, 64-bit | `lspci -vv -s 00:14.5`, `/sys/.../resource` |
| BAR2 | `ca800000`, 4 KiB, 64-bit | idem |
| BAR1 | **não existe** (sem região) | idem |
| MSI | `Count=2/2`, Maskable+, 64-bit+ | `lspci -vv` |
| Driver ligado | nenhum (`/sys/.../driver` não existe) | sysfs |
| `/sys/class/dma` | **inexistente** (nenhum engine registrado) | sysfs |
| `CONFIG_DMADEVICES=y` | habilitado no kernel | `/proc/config.gz` |
| Subfunções | `BPCIE_SUBFUNC_DMAC1 = 0`, `BPCIE_SUBFUNC_DMAC2 = 1`, marcadas **"confirmed"** | `drivers/ps4/baikal.h` |
| Região do DMAC na glue | **não configurada** no código do Baikal. Só existe para Aeolia: `ps4-apcie.c:500–503` (`glue_set_region(AEOLIA_FUNC_ID_DMAC, …)` com `0xbfa05000` e `0xbfa06000`) | árvore do kernel |
| Tratamento de IRQ do DMAC na bpcie | **existe**: `bpcie_handle_edge_irq()` tem o ramo `else if (func == 5) // Baikal DMA Controller` (`mask = 3`, `vector_to_write = 3`, `shift = 0`), em `ps4-bpcie.c:110` | leitura do código |

---

## 2. Correções ao plano original

1. **BAR1 não existe.** O plano dizia "BAR0 = canal 1, BAR1 = page regs, BAR2 = canal 2?". Medido: a região está em **BAR0 e BAR2**, e não há BAR1.
2. **Padrão de mapeamento:** no Aeolia, a glue usa `region 0` e `region 2` do DMAC e zera `1` e `3` (`ps4-apcie.c:500–503`). O Baikal segue o mesmo padrão nos BARs.
3. **Falta a configuração de glue.** No Aeolia, o DMAC só é utilizável depois de `glue_set_region()`. No Baikal não existe equivalente no código. Sem isso, o driver pode ler zeros ou travar.
4. **O mapa antigo era um engano de leitura, corrigido em 2026-11-13.** As faixas `0x0000–0x001F` ("DMA Channel 1"), `0x0080–0x008F` ("DMA Page Registers") e `0x00C0–0x00DF` ("DMA Channel 2") do `hardware_report.txt` estão na seção **"I/O PORTS"** do `/proc/ioports`, junto de `PIC1`, `PIT`, `8042` e `RTC CMOS`: são as portas do **DMA legado do PC (8237)**, não registradores do `00:14.5`. O `00:14.5` não tem BAR de I/O (`lspci`: só `Region 0` e `Region 2`, ambos memória). Os registradores reais estão em `+0x80…+0xac` de cada BAR (ver `baikal_dmac_mtk_registers_20261113.md`). As linhas originais permanecem no `hardware_report.txt` **anotadas como erro**, para registrar a origem do equívoco.
5. **IRQ (correção da correção):** o plano original estava certo. O `ps4-bpcie.c:110` já tem o ramo do DMAC no demux (`func == 5`). Uma versão anterior desta revisão dizia o contrário porque a busca foi só por nome (`DMAC`) e não leu o código. O que **não** foi verificado: se esse ramo funciona na prática, e como as subfunções `DMAC1/DMAC2` chegam ao driver.

---

## 2a. Status em 2026-11-13: RE do mapa de registradores concluído, driver NÃO escrito

- **Feito:** mapa de registradores e sequência de início de transferência decodificados do `dmac_mtk.c` do Orbis, e **12 registradores lidos em cada BAR** (somente leitura). Detalhes: `others/rea/dma/decompiled/baikal_dmac_mtk_registers_20261113.md`. Leituras no banco (`readonly_verification`).
- **Correção:** os registradores ficam em `+0x80…+0xac` de cada BAR (não `0x00–0x1F`/`0xC0–0xDF`). O mapa antigo do `hardware_report.txt` não vale.
- **ATUALIZAÇÃO (mesmo dia, autorizado pelo usuário): memcpy por descritor FUNCIONA nos dois controladores.** Teste de 256 bytes com buffers próprios (harness `baikal_dmac_test`). Sem glue, clock, `EN` ou reset prévios. Detalhes e o que ainda não foi testado: `baikal_dmac_mtk_registers_20261113.md`. Isso desfaz o "bloqueio" que eu havia registrado: não havia configuração prévia a fazer.
- **ATUALIZAÇÃO 2 (2026-11-13): o driver `dmaengine` `baikal-dmac` v0.1 existe e foi VALIDADO ao vivo.** Encadeamento, tamanhos até 1 MiB, alinhamentos e MSI (BAR0) já tinham passado no harness. O driver real (`drivers/dma/baikal-dmac.c`, patch `kernel/patches/baikal-dmac.patch`) carregou no kernel da tag `20261113-dmaengine`, registrou `dma0chan0` e `dma0chan1` e passou no `dmatest` do kernel: **3000 testes, 0 falhas** (canal 0 por IRQ, canal 1 por polling, **os dois ao mesmo tempo com 4 threads cada**, e buffers de 256 KiB). O canal do DMAC2 conclui por polling até a IRQ dele ser resolvida (pendente no `BACKLOG.md`).
- **Ainda não feito:** `CON` diferente do alinhamento, `len=0`, erro induzido, a IRQ do DMAC2, e persistir os módulos no rootfs. O harness continua sendo ferramenta de RE, não driver.
- **⏸️ Frente pausada em 2026-11-13 (decisão do usuário).** Utilidade avaliada, hipóteses e o próximo passo sugerido (DMA lendo a SPM, só leitura) estão no item "Baikal DMA" do `BACKLOG.md`. Para recompilar os módulos fora da árvore: `others/rea/dma/harness/build_dma_modules.sh`.

## 2b. Hipótese que enfraquece o plano (2026-11-13) — substituída pela seção 2a

**Atenção: uma versão anterior desta seção afirmava que o DMAC era um 8237 legado. Isso está DESCARTADO** com evidência do dump do Orbis (`others/rea/dma/decompiled/baikal_dmac_orbis_strings_20261113.md`):
- é um **DMA por descritores** (`dmac_mtk.c`, `DMA_DESC_ADDR`, `DMA_SRC_ADDR`, `DMA_DST_ADDR`, `DMA_LEN`, `DMA_CON`, `DMA_EN`, `DMA_RST`, `DMA_INT_FLAG`, descritor com `bcount/src/dst/next`) com interrupção (`dmac_interrupt`);
- o sufixo `mtk` sugere IP MediaTek; o mainline tem `mtk-cqdma.c` (nomes parecidos) como **pista de estudo**, sem presumir que os offsets sejam iguais;
- no Orbis é usado em `aeolia_dmac_xfer_upstream/downstream` (swap de memória em HDD, escrita no HDD, diagnóstico).

Consequência: o plano de `dmaengine` com `DMA_MEMCPY` **volta a fazer sentido em princípio**, mas **todos os offsets de registrador continuam desconhecidos** (os do `hardware_report.txt` não estão validados). Nenhuma leitura de registrador foi feita no PS4. O ganho prático para o Linux também **não está demonstrado**: a hipótese de que o DMAC move dados entre a RAM e a SPM é uma leitura dos nomes, sem decompilação.

## 3. Fases

### Fase 0 — Leitura somente
- [ ] Consultar `others/rea/ps4_hardware_memory.db` antes de ler MMIO (regra do `AGENTS.md`). Hoje não há linhas de DMA em `decompiled_functions`.
- [ ] Ler `BAR0` e `BAR2` (32 bits) com `setpci`/mmap, **sem escrita**, e comparar com a região de 4 KiB.
- [ ] Olhar `/proc/interrupts` para vetores do `00:14.5`.

### Fase 1 — Descobrir a configuração de glue (RE)
- [ ] Achar no Orbis a rotina equivalente a `glue_set_region` para o DMAC do Baikal. Pistas já registradas: strings `baikal_dmac_pci`, `Baikal DMA1/2 controller` (`others/rea/dma/decompiled/baikal_mem_fase2_orbis_strings.md`) e `res_alloc_helper_dc5ba5e0.txt`.
- [ ] Documentar o endereço e o valor de região em `others/rea/dma/decompiled/`.
- [ ] Registrar as funções pendentes na tabela `decompiled_functions` do SQLite.

### Fase 2 — Probe mínimo (somente leitura)
- [ ] `drivers/dma/baikal-dma.c` como `pci_driver`, com `CONFIG_BAIKAL_DMA=m`.
- [ ] Probe: `pci_enable_device`, `pci_request_regions`, `pci_ioremap_bar(0)` e `pci_ioremap_bar(2)`. Só lê identificação e registra os valores no `dmesg`.
- [ ] Não registrar `dma_device` ainda.

### Fase 3 — `dmaengine` memcpy
- [ ] `dma_device` com `DMA_MEMCPY`, `device_alloc_chan_resources`, `device_prep_dma_memcpy`, `device_issue_pending`, `device_tx_status`.
- [ ] Testar com `dmatest`. Critério: `dmesg` mostra `dmatest: Started`, sem erros, e o checksum bate.

### Fase 4 — IRQ
- [ ] Tratar o vetor DMAC no `ps4-bpcie.c` (subfunções `DMAC1 = 0`, `DMAC2 = 1`).
- [ ] Critério: `/proc/interrupts` incrementa durante o `dmatest`.

### Fase 5 — Slave e cíclico (depois)
- [ ] `device_prep_slave_sg` e `device_prep_dma_cyclic`, se houver periférico conectado. Só depois de validar a Fase 3.

---

## 4. Riscos

| Risco | Mitigação |
|---|---|
| Escrita em registrador do DMAC trava o barramento PCIe (lição de 2026-07-21) | Fases 0 e 2 só leem. Escrita só depois de confirmar o mapa |
| Região de glue não configurada → leitura de zeros ou travamento | Fase 1 antes de qualquer escrita. Não tocar na glue sem o valor do Orbis |
| IRQ compartilhada com o demux da bpcie | Fase 4 só depois de funcionar sem IRQ (polling) |
| Driver escrito sem validação de contexto | Compilar o arquivo isolado e gerar patch com `git diff HEAD` (regra do `AGENTS.md`) |

---

## 5. Fontes

**Web**
- [fail0verflow/ps4-linux, `drivers/ps4/aeolia.h`](https://github.com/fail0verflow/ps4-linux/blob/412b34111c0b0e646f94a258b23589d9e8fa10f9/drivers/ps4/aeolia.h): confirma `PCI_DEVICE_ID_ADMAC = 0x90a2` e a função `AEOLIA_FUNC_ID_DMAC = 5`. É o único registro encontrado sobre o DMAC da família. Não traz mapa de registradores.
- [postmarketOS MR 5194](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/merge_requests/5194): estrutura `drivers/ps4/` do Aeolia (`ps4-apcie.c`).
- [Gcsman110/ps4-mts-linux-driver](https://github.com/Gcsman110/ps4-mts-linux-driver): só descreve o DMA de descritores da GBE, não o DMAC.
- Buscas genéricas por "Baikal DMA 104d:90dc" retornaram apenas drivers de others fabricantes (DesignWare, Promise SX4, Switchtec). Foram descartados.

**Projeto**
- `kernel/kernel_build_7.0/include/linux/pci_ids.h:948`: `PCI_DEVICE_ID_SONY_BAIKAL_DMAC 0x90dc`.
- `kernel/kernel_build_7.0/drivers/ps4/baikal.h`, `ps4-apcie.c:500–503`.
- `others/rea/dma/decompiled/`, `others/rea/dma/scans/hardware_report.txt`.
