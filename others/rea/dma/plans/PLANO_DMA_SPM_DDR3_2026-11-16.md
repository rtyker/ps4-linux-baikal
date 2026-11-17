# Plano — Usar o **Aeolia DMAC (`00:14.7`)** para acessar a SPM/DDR3 (`00:14.6`)

**Data:** 2026-11-16 · **Status:** ✅ **CONCLUÍDO em 2026-11-16** — o DMAC do Baikal (`00:14.5`) lê e escreve a SPM em `0xC0000000 + off` e já está integrado no `baikal-memory` (ver §8 e §9). O "pivot" para o Aeolia DMAC descrito abaixo foi **superado** pelos resultados e não foi executado. Texto histórico das seções 1 a 7 e 11 a 14 mantido sem alteração.  
**Descoberta Crítica (2026-11-16):** O kernel Orbis usa o **Aeolia DMAC** (device composto xHCI+AHCI em `00:14.7`, device ID `0x90ce` ou `0x90a3`), **NÃO** o DMAC standalone `00:14.5` (`104d:90dc`). Ver `others/rea/dma/docs/CRITICAL_FINDING_AEOLIA_DMAC_2026-11-16.md`.

**Origem da ideia:** writeup do Debarshi para o PS4 Pro/Belize. Lá, mover a leitura da DDR3 do southbridge de CPU-PIO para DMA subiu a vazão de ~10,6 MB/s para ~504 MB/s. O writeup cita device `104d:90cd` — no Baikal, o equivalente é o **Aeolia DMAC**.

**Pergunta que o plano responde (CORRIGIDA):** O **Aeolia DMAC** (2 controladores: DMA1/DMA2, parte do `00:14.7`), que o Orbis usa via `aeolia_dmac_xfer_upstream()` para DDR3 swap, consegue ter a **janela BAR2 da SPM** (`00:14.6`, `0x80000000`) como origem/destino? E isso é mais rápido que o `memcpy_fromio` do `baikal-memory`?

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

## 2. O que já temos (verificado no repo em 2026-11-16) — **ATUALIZADO PÓS-DESCOBERTA**

| Peça | Estado | Onde |
|---|---|---|
| **Aeolia DMAC** (`00:14.7`, device ID `0x90ce` ou `0x90a3`), 2 controladores (DMA1/DMA2) | **NUNCA TESTADO** — usado pelo Orbis para DDR3 swap via `aeolia_dmac_xfer_upstream()` | `others/rea/dma/docs/CRITICAL_FINDING_AEOLIA_DMAC_2026-11-16.md` |
| DMAC Standalone `104d:90dc` (`00:14.5`), 2 controladores (BAR0 `ca000000`, BAR2 `ca800000`, 4 KiB) | Memcpy host↔host validado: ~888–935 MB/s, **MAS NÃO É O USADO PELO ORBIS PARA SPM** | `others/rea/dma/decompiled/baikal_dmac_mtk_registers_20261113.md` |
| Descritor (DMAC standalone) | 16 B: `+0` origem, `+4` destino, `+8` tamanho, `+0xC` próximo. Endereços 32 bits | idem |
| Interrupção (DMAC standalone) | MSI funciona no BAR0; não chega no BAR2 → polling | `harness/.../README.md` |
| Driver `baikal-dmac` (dmaengine) | Patch v0.1 para DMAC standalone | `kernel/patches/baikal-dmac.patch` |
| Harness de RE (DMAC standalone) | Módulo out-of-tree, buffers host↔host | `harness/baikal_dmac_test/baikal_dmac_test.c` |
| **SPM `00:14.6` (`104d:90dd`)** | BAR2 PCI `0x80000000–0x8fffffff` (256 MB reais); `baikal-memory` mapeia primeiros 4 MiB | `others/rea/spm/HANDOFF.md`; `drivers/misc/baikal-memory.c:506` |
| Caminho de leitura da SPM (CPU) | `memcpy_fromio()` → bounce 64 B → `copy_to_user()` | `drivers/misc/baikal-memory.c:154-177` |
| Escrita na SPM | `allow_write=0` padrão, restrita ao BAR2 (4 MiB) | idem |
| Resíduos Orbis no DMAC standalone | BAR2: `SRC=0x10040000`, `DST=0xcbc00000`; BAR0: `DST=0x00100000`, `LEN=0xffffffff` | Leitura ao vivo 2026-11-13 |

**Lacuna central:** Nunca testamos o **Aeolia DMAC** (o motor real do DDR3 swap) com o BAR2 da SPM. Também nunca medimos a vazão do caminho `memcpy_fromio` da SPM.

---

## 3. Hipóteses e o que pode dar errado (ATUALIZADO)

| # | Hipótese | Como falha | Consequência |
|---|---|---|---|
| H1 | O **Aeolia DMAC** consegue ler/escrever em `0x80000000+off` (P2P PCI dentro do southbridge) | Root complex não roteia P2P; ou SPM não responde a acesso DMA do Aeolia | `INT_FLAG` erro (`0x1e`) ou timeout, possível trava/MCE |
| H2 | O Aeolia DMAC enxerga a DDR3 num endereço **interno** diferente do PCI (Orbis usa `aeolia_dmac_xfer_upstream` com endereços próprios) | Usar `0x80000000+off` não bate com o que o Aeolia espera | Cópia de lixo ou erro. Não perigoso, só inútil |
| H3 | O ganho de banda é real (Orbis atinge ~500 MB/s no Belize equivalente) | SPM só responde bem a acessos pequenos; Aeolia DMAC limitado por ela | Sem ganho. Resultado negativo ainda vale registrar |
| H4 | O writeup cita device `90cd` (Belize) e GO `0x1d40` — **no Baikal o equivalente é Aeolia DMAC com registradores próprios** | Registradores Aeolia diferentes; GO em offset desconhecido | Caminho não se transfere 1:1. Precisa RE do Aeolia DMAC |

---

## 4. Passos (REVISTOS — Alvo = Aeolia DMAC `00:14.7`)

### Passo 0 — sem PS4: validar a fonte e preparar o banco ✅ **CONCLUÍDO**
1. Ler a página original do writeup diretamente ✅ → `others/rea/dma/docs/WRITEUP_DEBARSHI_DDR3_2026-11.md`
2. Consultar `ps4_hardware_memory.db` ✅ → Nenhuma leitura prévia de Aeolia DMAC ou SPM BAR2 via DMA
3. **NOVO:** Busca no dump Orbis ✅ → **Descoberta crítica: Orbis usa Aeolia DMAC (`aeolia_dmac_xfer_upstream`), não DMAC standalone**
   - Strings: `SceDdr3Swap`, `ddr3swap_*`, `aeolia_dmac_xfer_upstream`, `aeolia_dmac_pci`, `Aeolia DMA1/2 controller`
   - PCI match function em `0xffffffffdc7c1090` mostra device IDs `0x90ce`/`0x90a3` para Aeolia
4. Documentar descoberta ✅ → `others/rea/dma/docs/CRITICAL_FINDING_AEOLIA_DMAC_2026-11-16.md`

### Passo 0.4 — RE do Aeolia DMAC (NOVO, sem PS4)
1. Identificar device ID exato do Aeolia: `0x90ce` ou `0x90a3` (ver PCI match em `0x4711c5`)
2. Extrair via Ghidra headless a função `aeolia_dmac_xfer_upstream` (vaddr `~0xffffffffdce32ea9` area)
3. Mapear registradores do Aeolia DMAC (BARs do device `00:14.7`)
4. Determinar: sequencia de init, registrador GO, formato de descritor, endereçamento da SPM
1. Ler a página original do writeup diretamente (não via resumo) e extrair: registradores, ordem de programação, tamanho do buffer, qual dispositivo PCI. Salvar em `others/rea/dma/docs/WRITEUP_DEBARSHI_DDR3_2026-11.md` com a URL e a data da leitura.
2. Consultar `others/rea/ps4_hardware_memory.db` (`readonly_verification`, `hardware_registers`) para qualquer leitura prévia de `+0x70` (`0x80000001`) e dos BARs da SPM, para não repetir varredura.
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

## 5. Riscos e mitigações (ATUALIZADO)

| Risco | Mitigação |
|---|---|
| P2P para o BAR2 trava o barramento ou causa MCE | Começar com 256 B, parar na primeira falha, console UART capturando (`others/scripts/uart_start.sh`), partir do baseline estável `20261116-keep-mode-aplicado` (SSH em `192.168.6.128`) |
| O Aeolia DMAC gravar na SPM fora da janela segura | Passo 3 só depois do Passo 2 e só na janela já validada, com guarda e readback |
| Conflito de driver no Aeolia (`00:14.7`) | `rmmod xhci_aeolia` / `rmmod ahci` ANTES do harness (cuidado: derruba USB/SATA); documentar no teste |
| Repetir leitura que já temos | Passo 0.2 antes de qualquer acesso |
| Confiar num número do resumo do writeup | Passo 0.1 concluído |

---

## 6. Critérios de aceite
- **Passo 2:** cópia SPM → host de ≥ 64 KiB bit a bit idêntica à leitura por CPU, sem erro no dmesg, e vazão medida e registrada.
- **Resultado final** (positivo ou negativo) em `test_history` + `ACHADOS_MEMORIA_BAIKAL_FASE2.md` + linha no `others/docs/BACKLOG.md`, sem apagar o que já foi descartado.

## 7. Fora de escopo
Integração no `baikal-memory`, `dmaengine` para a SPM, swap/zram sobre a SPM e qualquer mudança em kernel (seguem a regra de patch idempotente) só depois do Passo 4.

---

## 11. Passo 0 — EXECUTADO EM 2026-11-16 (resultados)

### 11.1 Passo 0.1 — Leitura das fontes originais ✅
Arquivo gerado: `others/rea/dma/docs/WRITEUP_DEBARSHI_DDR3_2026-11.md`

**Principais achados:**
| Item | Valor Citado | Status para nosso caso |
|------|--------------|------------------------|
| Device ID DMAC (Belize) | `104d:90cd` | **MAPEIA PARA AEOLIA DMAC** no Baikal (`0x90ce`/`0x90a3`) |
| Registrador GO | `0x1d40` | **REGISTRADOR DO AEOLIA** — não existe no DMAC standalone |
| Interrupt-mask | `0x11` | Desconhecido no Aeolia — precisa RE |
| Endereço interno DDR3 | `0xC0000000 + off` | Candidato H2 — pode ser endereço interno do Aeolia |
| DDR3 size | 1 GB | Nosso Baikal Slim: 256 MB |
| Alinhamento | 32-bit obrigatório | Aeolia DMAC também exige (igual ao standalone) |
| Kernel base | 6.8.12 | Nosso: 7.0.8 |

**Pistas aproveitáveis confirmadas:**
1. Base PCI `0x80000000` coincide (mesma convenção de janela)
2. Hipótese H2: DMA addr = PCI addr + `0x40000000` (dois números frágeis)
3. Assimetria posted/non-posted: medir leitura e escrita separadamente

### 11.2 Passo 0.2 — Consulta ao banco SQLite ✅
```sql
-- readonly_verification: NENHUMA leitura prévia de Aeolia DMAC ou SPM BAR2 via DMA
-- hardware_registers: DMAC standalone/Glue registrados, mas Aeolia DMAC NÃO
-- decompiled_functions: ZERO funções com Aeolia/DDR3/SPM/swap no role/category
-- test_history: Testes DMAC standalone 80-83 (2026-11-13) = SUCESSO host↔host
-- bar_regions: SPM BAR2 = 0x80000000 (256 MB reais); Aeolia em 00:14.7 BAR2 = 0xce800000
```

**Resíduos Orbis no DMAC STANDALONE (lidos 2026-11-13):**
- BAR2: `SRC=0x10040000`, `DST=0xCBC00000`, `LEN=0`
- BAR0: `DST=0x00100000`, `LEN=0xFFFFFFFF`
- Repetidos após reboot → resíduo do Orbis pré-kexec
- **NOTA:** Estes resíduos são do DMAC standalone (00:14.5), NÃO do Aeolia DMAC usado para DDR3 swap

### 11.3 Passo 0.3 — Busca no dump Orbis ✅ **CONCLUÍDO — DESCOBERTA CRÍTICA**
- **ACHADO:** Orbis usa **Aeolia DMAC** (`aeolia_dmac_xfer_upstream`) para DDR3 swap
- Strings encontradas: `SceDdr3Swap`, `ddr3swap_*`, `aeolia_dmac_xfer_upstream`, `aeolia_dmac_pci`, `Aeolia DMA1/2 controller`
- PCI match function em `0xffffffffdc7c1090` mostra device IDs `0x90ce`/`0x90a3` para Aeolia
- Documentado em: `others/rea/dma/docs/CRITICAL_FINDING_AEOLIA_DMAC_2026-11-16.md`

### 11.4 Passo 0.4 — RE do Aeolia DMAC (NOVO, EM ANDAMENTO)
1. Identificar device ID exato: `0x90ce` ou `0x90a3` (PCI match em `0x4711c5`)
2. Extrair via Ghidra headless: `aeolia_dmac_xfer_upstream` (vaddr ~`0xffffffffdce32ea9`)
3. Mapear registradores do Aeolia DMAC (BARs do device `00:14.7`)
4. Determinar: sequencia de init, registrador GO, formato de descritor, endereçamento SPM

---

## 12. Artefatos gerados neste Passo 0

| Arquivo | Descrição |
|---------|-----------|
| `others/rea/dma/docs/WRITEUP_DEBARSHI_DDR3_2026-11.md` | Documentação completa das 3 fontes originais + análise de diferenças |
| `others/rea/dma/docs/CRITICAL_FINDING_AEOLIA_DMAC_2026-11-16.md` | **Descoberta crítica: alvo é Aeolia DMAC, não DMAC standalone** |
| `others/rea/dma/harness/baikal_dmac_test/baikal_dmac_test_spm.c` | **OBSOLETO** — testava DMAC errado (standalone 00:14.5) |
| `others/rea/dma/harness/baikal_dmac_test/Makefile.spm` | **OBSOLETO** — para harness obsoleto |
| **NOVO NECESSÁRIO:** Harness para Aeolia DMAC (`00:14.7`) | A criar após Passo 0.4 |

---

## 13. Próximas ações (REVISTAS — Alvo = Aeolia DMAC `00:14.7`)

| Passo | Ação | Responsável | Estimativa |
|-------|------|-------------|------------|
| **0.4** | Ghidra headless no dump Orbis: extrair `aeolia_dmac_xfer_upstream`, mapear registradores Aeolia | RE analyst | 60-90 min |
| **1** | Baseline CPU: medir `memcpy_fromio` + bounce + `copy_to_user` do `baikal-memory` (1 MiB, 5x) | PS4 operator | 15 min |
| **2** | **Aeolia DMAC** lendo SPM: testar H1 (`0x80000000+off`), H2 (endereço interno Aeolia), com harness novo | PS4 operator | 45-60 min |
| **3** | Se Passo 2 passar: Aeolia DMAC escrevendo SPM (janela 4 MiB, readback CPU) | PS4 operator | 20-30 min |
| **4** | Decisão e documentação final | Lead | 15 min |

**Pré-condições para Passo 1:**
- PS4 com baseline `20261116-keep-mode-aplicado` no HD
- `baikal-memory` carregado (`allow_write=0` padrão)
- **Aeolia drivers (`xhci_aeolia`, `ahci`) DESCARREGADOS** antes do harness (cuidado: perde USB/SATA)
- UART capturando (`uart_start.sh`)
- SSH WiFi em `192.168.6.128` funcionando

---

## 14. Resumo da Mudança de Alvo

| Aspecto | Plano Original (OBSOLETO) | Plano Corrigido (ATUAL) |
|---------|---------------------------|-------------------------|
| **Motor DMA** | DMAC Standalone `00:14.5` (`104d:90dc`) | **Aeolia DMAC `00:14.7` (`104d:90ce`/`90a3`)** |
| **Usado pelo Orbis para DDR3 swap?** | ❌ Não | ✅ Sim (`aeolia_dmac_xfer_upstream`) |
| **Controladores** | 2 (BAR0, BAR2) | 2 (DMA1, DMA2) — mesma arquitetura |
| **Registrador GO** | `0x1d40` (não existe no standalone) | **Existe no Aeolia** — offset a determinar |
| **Harness existente** | `baikal_dmac_test_spm.c` (OBSOLETO) | **Novo harness necessário** para Aeolia |
| **Driver dmaengine** | `baikal-dmac.patch` (para standalone) | **Novo driver ou estender** para Aeolia |
| **Conflito de driver** | `rmmod baikal_dmac` | `rmmod xhci_aeolia ahci` (derruba USB/SATA!) |

---

## 8. Resultados ao vivo — 2026-11-16 (kernel `20261116-s5-dma`)

Harness: `others/rea/dma/harness/baikal_dmac_test/baikal_dmac_test_spm.c` (somente leitura da SPM, polling, DMAC1/BAR0), com `baikal_dmac` descarregado.

| Teste | `spm_base` | Resultado | `test_history` |
|---|---|---|---|
| H1 | `0x80000000` (endereço PCI do BAR2) | **FALHOU**: erro imediato do DMAC (`INT_FLAG=0x2`, `DEBUG_ST=0x13`) na 1ª transferência de 256 B. PS4 estável. **H1 refutada** | 87 |
| H2 | `0xC0000000` (endereço do writeup) | **PARCIAL**: 4/4 transferências sem erro e iguais à leitura da CPU. 256 B 53 MB/s, 4 KiB 660 MB/s, 64 KiB 1426 MB/s, **1 MiB 1514 MB/s**. CPU `memcpy_fromio`: **~4 MB/s**. Mas o trecho (0–1 MiB) é todo `0x00`, então a igualdade não prova o mapeamento | 88 |

**Observações:**
- A vazão do H2 (~1,5 GB/s) bate com o teto de ~1,4 GB/s do Debarshi (Belize). A CPU (~4 MB/s) é da mesma ordem dos 10,6 MB/s dele.
- Depois do reset `RST=2→0`, o DMAC volta a `DST=0x00100000` e `LEN=0xffffffff`, os mesmos valores do "estado inicial". Os "resíduos do Orbis" da leitura de 2026-11-13 podem ser **valores de reset**.

**Próximo (em execução):** provar o mapeamento do H2 com dados não nulos. Gravar um padrão aleatório de 4 KiB via `baikal-memory` com `allow_write=1` (janela BAR2 já validada na Fase 5), ler pelo DMA em `0xC0000000 + offset`, comparar, e restaurar o conteúdo original.

### 8.1 Prova do H2 e escrita (Passo 3) — 2026-11-16

| Teste | Resultado | `test_history` |
|---|---|---|
| H2 com dados reais: 4 KiB aleatórios gravados em BAR2+0x200000 (via `baikal-memory allow_write=1`), lidos pelo DMA em `0xC0000000+0x200000` | **SUCESSO**: 2/2 PASS, dump DMA = padrão (`36 fd 20 86…`). **Mapeamento provado: o DMAC vê a SPM em `0xC0000000` = BAR2 PCI + `0x40000000`** | 89 |
| Passo 3: DMA host → SPM (`write=1`, só em `0x200000`, até 64 KiB) | **SUCESSO**: 3/3 PASS, guarda intacta. DMA 64 KiB **912 MB/s**; CPU `memcpy_toio` ~81 MB/s | 90 |

**Vazão consolidada (64 KiB–1 MiB):**

| | Leitura da SPM | Escrita na SPM |
|---|---|---|
| CPU (caminho atual do `baikal-memory`) | ~4 MB/s | ~81 MB/s |
| DMAC1 por polling | **~1,5 GB/s** | **~0,9 GB/s** |

Estado deixado: janela restaurada a zero (conferida), `baikal-memory` de volta a `allow_write=N`, `baikal_dmac` recarregado.

**Decisão do Passo 4:** DMA é ~375× (leitura) e ~11× (escrita) mais rápido que a CPU → **integrar no `baikal-memory`** (leitura/escrita em bloco via DMAC usando `0xC0000000 + off`, com fallback para `memcpy_fromio`). Fica para um plano próprio, via patch idempotente.

---

## 9. Fechamento do plano (2026-11-16)

| Passo | Estado | Evidência |
|---|---|---|
| 0 — fonte e banco | ✅ | writeup lido, banco consultado |
| 0.4 — RE do Aeolia DMAC (`00:14.7`) | ⏹ **não executado e não necessário** | os passos 2 e 3 passaram com o DMAC do Baikal (`00:14.5`); o "pivot" do cabeçalho antigo foi superado. Nada foi medido no Aeolia DMAC; fica como pesquisa opcional |
| 1 — baseline da CPU | ✅ | `test_history` 94: leitura da CPU a 4,1 MB/s (1 MiB). Não entrou em `readonly_verification`, que guarda valores de registradores, não vazão |
| 2 — DMAC lendo a SPM | ✅ | `test_history` 87–89: H1 (`0x80000000`) refutada; H2 (`0xC0000000`) provada com padrão aleatório |
| 3 — escrita pela SPM | ✅ | `test_history` 90 (e 95 já pelo `baikal-memory`) |
| 4 — decisão | ✅ integrar | feita em `others/rea/spm/plans/PLANO_BAIKAL_MEMORY_DMA_2026-11-16.md`, resultados na §5.1 (`test_history` 94–97) |

**Critérios de aceite (§6):** cópia de ≥ 64 KiB idêntica à da CPU ✅ (padrão aleatório, mesmo SHA-256, sem erro no `dmesg`); resultado registrado em `test_history` ✅ (87–97), `ACHADOS_MEMORIA_BAIKAL_FASE2.md` ✅ (§9 novo) e no `BACKLOG.md` ✅.

**Vazão final integrada no `/dev/baikal-memory`** (inclui `dd` e `copy_to_user`; o DMAC puro do harness mede ~1,5 GB/s): leitura de 1 MiB 547 a 624 MB/s, de 4 MiB 887 a 924 MB/s, contra ~4,1 MB/s pela CPU (~130× a ~220×).

**Gravação no HD (feita em 2026-11-16):** com o HD plugado no PC, `distro/scripts/install-modules-7.0.sh` (backup dos módulos antes; `rc=0`) e `distro/deploy-boot-7.0.sh 20261116-dma-final` (`md5` conferido, partições desmontadas). `bootargs` e `initramfs` são cópias da `20261116-dma-test`. O aviso do script de build sobre `bzImage` "acima de 10 MB" não se confirma: a tag tem 10,56 MiB, igual ao kernel que rodava, e tags de 15 MiB também subiram.

**Única pendência:** o primeiro boot da tag no console (recolocar o HD no PS4) e a validação final: módulo com `use_dma=Y` e `ativo DMAC1` sem parâmetros, leitura de 1 MiB a ~550 MB/s.
