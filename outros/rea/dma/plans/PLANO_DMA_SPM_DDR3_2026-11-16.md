# Plano — Usar o DMAC (`00:14.5`) para acessar a SPM/DDR3 (`00:14.6`)

**Data:** 2026-11-16 · **Status:** 🟡 Plano para revisão. **Nada executado, nada compilado.**
**Origem da ideia:** writeup do Debarshi para o PS4 Pro/Belize (ver §1). Lá, mover a leitura da DDR3 do southbridge de CPU-PIO para DMA subiu a vazão de ~10,6 MB/s para ~504 MB/s.
**Pergunta que o plano responde:** o DMAC do Baikal (`104d:90dc`), que já faz memcpy a ~900 MB/s entre buffers de RAM, consegue ter a **janela BAR2 da SPM** como origem ou destino? E isso é mais rápido que o `memcpy_fromio` do `baikal-memory`?

---

## 1. O que o writeup diz (e o que não diz)

Fonte: <https://dev.to/debarshis/ps4-pro-belize-ddr3-patch-v2-4pb2> (cobertura: <https://ps4linux.com/ps4-pro-ddr3-patch-linux-debarshi/>).

> ⚠️ O conteúdo abaixo veio de um resumo automático da página, **não de leitura direta**. Todo valor de registrador precisa ser conferido na fonte (Passo 0) antes de ser usado.

| Item | Valor citado | Observação |
|---|---|---|
| Gargalo antigo | CPU lê a DDR3 do southbridge de 8 em 8 bytes por uma janela PCI pequena | ~10,6 MB/s leitura, ~138 MB/s escrita |
| Solução | driver para o motor DMA do southbridge + 1 buffer de staging fixo < 4 GB, coerente | 504 MB/s leitura, 425 MB/s escrita, teto ~1,4 GB/s |
| Dispositivo | PCI `104d:90cd` | **Não existe em nenhum lugar do nosso repo** |
| Registrador de disparo | `0x1d40` | Fora dos 4 KiB dos BARs do nosso DMAC (`90dc`) |
| Máscara de interrupção | escrever `0x11` | — |
| Chip da DDR3 | `0xC0000000 + offset` no barramento interno | Não é o endereço PCI. O nosso BAR2 está em `0x80000000` |
| Hardware | Belize (Pro), DDR3 de 1 GB | Nosso Baikal Slim tem 256 MB |

**Não consta no writeup (e por isso não podemos assumir):** mapa completo de registradores, tamanho do buffer, sequência de init, patches, versão do kernel.

### 1.1 Série completa do autor (descoberta em 2026-11-16)

Há **3 posts** (<https://dev.to/debarshis>), todos lidos via resumo automático. Nenhum traz código, repositório ou nome de patch.

| Post | Data (sem ano na listagem) | Conteúdo útil |
|---|---|---|
| [PS4 Pro Belize DDR3](https://dev.to/debarshis/ps4-pro-belize-ddr3-170m) (v1) | 4 ago | A faixa `0x80000000–0xDFFFFFFF` vem como `SMAP_TYPE_RESERVED` no E820; o patch no `linux_boot.c` do payload kexec recorta 1 GB (base `0x80000000`, tamanho `0x40000000`) como memória. O controlador **rejeita acessos não alinhados a 32 bits** (I/O error), então usa `ioread32`/`iowrite32` em palavras. Exposto como disco blk-mq `/dev/ps4pro_ddr3` para swap. Kernel 6.8.12. Sem medição |
| [DDR3 Memory Engine Architecture](https://dev.to/debarshis/ddr3-memory-engine-architecture-dg2) | 11 ago | Escrita *posted*: rajada > 1 GB/s, sustentado ~156 MB/s. Leitura *non-posted*: ~11 MB/s, latência média 85 ms. 8 filas, zswap LZ4, prefetch de 4 MB. Sem registradores |
| [Belize DDR3 patch v2](https://dev.to/debarshis/ps4-pro-belize-ddr3-patch-v2-4pb2) | 24 out | Troca o PIO por DMA: 504 MB/s leitura, 425 MB/s escrita (ver §1) |

**Confiabilidade:** o próprio resumidor marcou várias afirmações como não verificáveis (sem logs, código ou metodologia). Tratar como **pistas**, não como fatos.

**Pistas aproveitáveis para o nosso caso:**
- O PCI `0x80000000` do Belize bate com o nosso BAR2 da SPM (`0x80000000`). Mesma convenção de janela.
- **Hipótese H2 nova (não verificada):** se o DMA usa `0xC0000000 + off` (v2) e a janela PCI é `0x80000000 + off` (v1), o endereço do DMA seria o PCI **+ `0x40000000`**. É uma conta com dois números de fontes frágeis. Testar só depois de H1 falhar e **só** esse candidato.
- Alinhamento de 32 bits: nosso `memcpy_fromio` não garante acessos de 32 bits e já funcionou nas nossas leituras, mas no Passo 1 vale medir também uma leitura com `readl()` explícito. O DMAC já exige múltiplos de 4 B.
- Assimetria posted/non-posted: **escrita pode ser muito mais rápida que leitura** por CPU. Medir as duas no Passo 1.

---

## 2. O que já temos (verificado no repo em 2026-11-16)

| Peça | Estado | Onde |
|---|---|---|
| DMAC `104d:90dc`, 2 controladores (BAR0 `ca000000`, BAR2 `ca800000`, 4 KiB cada) | Memcpy por descritor validado: cadeia de descritores, até 1 MiB, alinhamentos 4–64 B, **~888 MB/s (64 KiB) e ~935 MB/s (1 MiB)** | `outros/rea/dma/decompiled/baikal_dmac_mtk_registers_20261113.md` |
| Descritor | 16 B: `+0` origem, `+4` destino, `+8` tamanho, `+0xC` próximo (0 = fim). Endereços de 32 bits | idem |
| Interrupção | MSI funciona no DMAC1 (BAR0); **não chega no DMAC2 (BAR2)** → usar polling | `harness/.../README.md` |
| Driver `baikal-dmac` (dmaengine) | Patch v0.1 | `kernel/patches/baikal-dmac.patch` |
| Harness de RE | Módulo out-of-tree, **só com buffers `dma_alloc_coherent` do host nas duas pontas** | `harness/baikal_dmac_test/baikal_dmac_test.c` |
| SPM `00:14.6` (`104d:90dd`) | BAR2 PCI `0x80000000–0xbfffffff` (1 GiB endereçado, **256 MB reais**); driver `baikal-memory` mapeia só os primeiros 4 MiB do BAR2 | `outros/rea/spm/HANDOFF.md`; `drivers/misc/baikal-memory.c:506` |
| Caminho de leitura da SPM | `memcpy_fromio()` → bounce de 64 B → `copy_to_user()` | `drivers/misc/baikal-memory.c:154-177` |
| Escrita na SPM | `allow_write=0` por padrão, restrita ao BAR2 | idem, `:43-50`, `:199` |
| Resíduos do Orbis nos registradores do DMAC | BAR2: `SRC=0x10040000`, `DST=0xcbc00000`. BAR0: `DST=0x00100000`, `LEN=0xffffffff` | doc do mapa, "Leitura ao vivo" |

**Lacuna central:** nunca testamos o DMAC com o BAR2 da SPM como uma das pontas. Também **nunca medimos** a vazão do caminho `memcpy_fromio` da SPM.

---

## 3. Hipóteses e o que pode dar errado

| # | Hipótese | Como falha | Consequência |
|---|---|---|---|
| H1 | O DMAC consegue ler/escrever em `0x80000000+off` (peer-to-peer PCI dentro do southbridge) | O root complex não roteia P2P para o mesmo dispositivo/ponte; ou a SPM não responde a esse tipo de acesso | `INT_FLAG` com erro (`0x1e`) ou timeout, possivelmente **trava de barramento/MCE** |
| H2 | O DMAC enxerga a DDR3 num endereço **interno** diferente do PCI (o writeup cita `0xC0000000`; os resíduos do Orbis são `0x10040000` e `0xcbc00000`) | Usar `0x80000000+off` não bate com o que o DMAC espera | Cópia de lixo ou erro. Não é perigoso, só inútil |
| H3 | O ganho de banda é real | A SPM só responde bem a acessos pequenos; o DMAC fica limitado por ela | Sem ganho. O resultado negativo ainda vale registrar |
| H4 | O writeup usa **outro** motor (`90cd`, go em `0x1d40`) | `0x1d40` não existe no nosso DMAC (BARs de 4 KiB) | O caminho do Debarshi não se transfere 1:1. O nosso teste é por analogia, não por cópia |

Nada aqui permite concluir que vai funcionar. O Passo 1 existe para responder H1 e H2 com risco controlado.

---

## 4. Passos

### Passo 0 — sem PS4: validar a fonte e preparar o banco
1. Ler a página original do writeup diretamente (não via resumo) e extrair: registradores, ordem de programação, tamanho do buffer, qual dispositivo PCI. Salvar em `outros/rea/dma/docs/WRITEUP_DEBARSHI_DDR3_2026-11.md` com a URL e a data da leitura.
2. Consultar `outros/rea/ps4_hardware_memory.db` (`readonly_verification`, `hardware_registers`) para qualquer leitura prévia de `+0x70` (`0x80000001`) e dos BARs da SPM, para não repetir varredura.
3. Procurar no dump do Orbis (Ghidra/objdump em `kmem_dump_1252.bin`) o consumidor do DMAC para a **SPM/ddr3swap**: strings já conhecidas (`SceDdr3Swap`, `ddr3swap_*`, `spm_pci`, `Baikal DDR3 memory`, ver `ACHADOS_MEMORIA_BAIKAL_FASE2.md`). Objetivo: descobrir **qual endereço** o Orbis entrega ao DMAC para a DDR3 (resolve H2 sem tocar no hardware).

> **Nomenclatura:** neste plano, "BAR2 da SPM" é o BAR2 do `00:14.6` (PCI `0x80000000`). "DMAC BAR0/BAR2" são os dois controladores do `00:14.5`. São coisas diferentes.

### Passo 1 — com PS4: baseline do caminho atual (somente leitura)
1. Medir a vazão de leitura do `baikal-memory` na SPM (dentro dos primeiros 4 MiB do BAR2, ex.: 1 MiB; o driver só mapeia 4 MiB). Atenção: o caminho passa pelo bounce de 64 B + `copy_to_user`, então o número inclui esse custo. Para uma comparação justa com o DMA, medir também um `memcpy_fromio` direto num módulo de teste. Repetir 5 vezes e anotar média e mínimo. Isso é o número a bater.
2. Registrar em `test_history` e criar a linha-base no `readonly_verification`.

### Passo 2 — com PS4: DMAC lendo da SPM (somente leitura da SPM)
Estender o harness (cópia nova do `.c`, sem alterar o original) com um modo `src_bar2=1`:
- Descritor com origem = `0x80000000 + off` (candidato H1), destino = buffer coerente do host (< 4 GiB).
- Tamanhos crescentes: 256 B → 4 KiB → 64 KiB → 1 MiB, **sempre dentro dos primeiros 4 MiB**. **Parar na primeira falha.**
- Comparar byte a byte com a leitura de CPU do mesmo trecho (via `baikal-memory`).
- Se H1 falhar, tentar os candidatos de H2 **um por vez**, só os que vierem do Passo 0 ou do §1.1 (`0xC0000000 + off`); nunca varrer endereços às cegas.
- Salvaguardas herdadas do harness: controlador ocioso, `LEN/SRC/DST` zerados e relidos, buffers mantidos se der timeout/erro, reset com `RST=2→0`.
- **Pré-condições adicionais:** `rmmod baikal_dmac` antes (disputam o `90dc`). Usar o controlador **BAR0** (MSI funciona, mas o teste vai por polling mesmo). Salvar o dmesg antes e depois.

### Passo 3 — com PS4: escrita pela SPM (só se o Passo 2 passar)
- Origem = buffer do host, destino = `0x80000000+off`, **apenas nos primeiros 4 MiB do BAR2 da SPM**, que é o único trecho que o `baikal-memory` aceita escrever mesmo com `allow_write=1` (`HANDOFF.md`, "Whitelist/regra de segurança"; a escrita com readback `0xCAFEBABE` da Fase 5 foi nessa janela). O DMAC **não passa pelas checagens do driver**, então o harness precisa impor o mesmo limite (recusar destino fora de `0x80000000..0x803fffff`) e usar um offset que já tenha sido lido e anotado antes de escrever.
- Readback pela CPU e comparação.

### Passo 4 — decisão
| Resultado | Ação |
|---|---|
| DMA funciona e é ≥ 5× mais rápido que o baseline | Integrar no `baikal-memory` (leitura/escrita em bloco via `dmaengine`), com fallback para `memcpy_fromio`. Plano próprio, via patch idempotente, conforme o AGENTS.md. |
| DMA funciona, ganho pequeno | Documentar e encerrar. Manter CPU-PIO |
| DMA falha em todos os endereços candidatos | Documentar H1/H2 como refutadas, com os endereços testados. Reabrir só com fonte nova |

---

## 5. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| P2P para o BAR2 trava o barramento ou causa MCE | Começar com 256 B, parar na primeira falha, console UART capturando (`outros/scripts/uart_start.sh`), partir do baseline estável `20261116-keep-mode-aplicado` (SSH em `192.168.6.128`) |
| O DMAC gravar na SPM fora da janela segura | Passo 3 só depois do Passo 2 e só na janela já validada, com guarda e readback |
| Conflito de driver no `90dc` | `rmmod baikal_dmac` antes de carregar o harness; documentar no teste |
| Repetir leitura que já temos | Passo 0.2 antes de qualquer acesso |
| Confiar num número do resumo do writeup | Passo 0.1 |

---

## 6. Critérios de aceite
- **Passo 2:** cópia SPM → host de ≥ 64 KiB bit a bit idêntica à leitura por CPU, sem erro no dmesg, e vazão medida e registrada.
- **Resultado final** (positivo ou negativo) em `test_history` + `ACHADOS_MEMORIA_BAIKAL_FASE2.md` + linha no `outros/docs/BACKLOG.md`, sem apagar o que já foi descartado.

## 7. Fora de escopo
Integração no `baikal-memory`, `dmaengine` para a SPM, swap/zram sobre a SPM e qualquer mudança em kernel (seguem a regra de patch idempotente) só depois do Passo 4.
