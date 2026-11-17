# Plano — `baikal-memory` lendo e escrevendo a SPM pelo DMAC

**Data:** 2026-11-16 · **Status:** ✅ Implementado e validado ao vivo (testes 1 a 10, `test_history` 94–97). Tag `20261116-dma-final` **gravada no HD** (`install-modules` + `deploy-boot`, `md5` conferido). **Validada no primeiro boot que subiu** (`test_history` 99): módulo sobe sem parâmetros com `use_dma=Y`, `ativo DMAC1` e 513–642 MB/s em 1 MiB. Ressalva: a 1ª tentativa de boot desligou o console sozinho, causa desconhecida. Resultados na §5.1.
**Base provada ao vivo** (`others/rea/dma/plans/PLANO_DMA_SPM_DDR3_2026-11-16.md` §8, `test_history` 87–90): o DMAC do Baikal (`00:14.5`) enxerga a SPM (`00:14.6`) em **`0xC0000000 + off`** (= BAR2 PCI `0x80000000` + `0x40000000`). Por DMA: leitura ~1,5 GB/s, escrita ~0,9 GB/s. Pela CPU, o caminho atual do `baikal-memory`: ~4 MB/s e ~81 MB/s.

**Objetivo:** `read()`/`write()` em `/dev/baikal-memory` na janela do BAR2 passam a usar o DMAC, com fallback automático para a CPU. Fora do BAR2 (BAR0, BAR5) nada muda.

**Critério de aceite:**
1. `dd if=/dev/baikal-memory bs=1M` na janela do BAR2 a ≥ 500 MB/s (hoje ~4 MB/s), com o resultado **idêntico byte a byte** ao do caminho pela CPU.
2. Escrita com `allow_write=1` idêntica no readback, e `allow_write=0` continua recusando com `-EPERM`, **também no caminho DMA**.
3. Sem o `baikal_dmac` carregado, o driver funciona como hoje (CPU), sem erro.
4. Nenhum oops, nenhum erro do DMAC no dmesg ao longo dos testes da §5.

---

## 1. Estado atual (lido no código em 2026-11-16)

**`drivers/misc/baikal-memory.c`** (vem do `kernel/patches/baikal-memory-fase2.patch`, `CONFIG_BAIKAL_MEMORY=m`):
- `struct baikal_mem_dev`: um `mutex lock`, BARs mapeados por `devm_ioremap` (BAR2 só os primeiros **4 MiB**).
- Layout de `/dev/baikal-memory`: BAR0 em `0x0`, **BAR2 em `0x1000`–`0x401000`** (`BAIKAL_DEV_BAR2_WIN = SZ_4M`), BAR5 em `0x500000`.
- `read()`/`write()`: `baikal_mem_resolve()` traduz o offset; cópia pela CPU com bounce de **64 B** (`memcpy_fromio`/`memcpy_toio` + `copy_to/from_user`). `write()` só funciona com `allow_write=1` e só no BAR2.
- `mmap()`: `remap_pfn_range` direto no BAR2. **Fica fora deste plano** (é acesso direto da CPU, sem cópia no driver).
- ⚠️ **Bug existente, achado na revisão deste plano:** para offsets na **lacuna `0x401000`–`0x4fffff`** (entre o fim da janela do BAR2 e o início do BAR5), o `baikal_mem_resolve()` cai no ramo do BAR5 e devolve `bar5 + (pos − 0x500000)`, um **deslocamento negativo**: leitura de MMIO fora do mapeamento, provável oops. Basta um `cat /dev/baikal-memory` ou um `dd` que atravesse a lacuna. Só afeta `read()` (o ramo do BAR5 recusa escrita). **Não testar isso no kernel atual.** A correção (devolver `NULL` na lacuna, o que faz o `read()` parar ali) entra neste mesmo patch, porque o caminho de leitura vai ser mexido de qualquer forma.

**`drivers/dma/baikal-dmac.c`** (vem do `kernel/patches/baikal-dmac.patch`, `CONFIG_BAIKAL_DMAC=m`, aplicado **depois** do `baikal-memory-fase2.patch`):
- `dmaengine` com `DMA_MEMCPY`, 2 canais: DMAC1 (BAR0, com IRQ e watchdog) e DMAC2 (BAR2, só polling a cada 20 µs).
- `prep_dma_memcpy(dst, src, len)`: endereços de 32 bits, `len` até 256 MiB (descritores de 1 MiB encadeados); `src`, `dst` e `len` **múltiplos de 4**; `copy_align = 4`.
- Erro do hardware (`INT_FLAG` bits 1–4) ou timeout de 2 s → reset do canal e descritor concluído com **`DMA_TRANS_ABORTED`**.
- Máscara DMA de 32 bits no próprio dispositivo do DMAC; o `00:14.5` não está atrás de IOMMU (endereço DMA = físico).

---

## 2. Desenho

### 2.1 Usar o `dmaengine`, não os registradores do DMAC
O `baikal-memory` pede um canal ao `dmaengine` e usa `dmaengine_prep_dma_memcpy()`. **Não** programa os registradores do DMAC por conta própria: isso duplicaria o driver e disputaria o `104d:90dc` com o `baikal-dmac` (o mesmo conflito que o harness de RE tem).

- **Qual canal:** `dma_request_channel(mask DMA_MEMCPY, filtro)`. O filtro aceita só canais cujo `chan->device->dev` é o PCI `104d:90dc`, **e** prefere o `chan_id 0` (DMAC1, com IRQ). Se só o DMAC2 estiver livre, usa-o (polling funciona; só é menos eficiente).
- **Quando pedir:** de forma preguiçosa, na primeira transferência que se qualifica, com nova tentativa nas seguintes se falhar. Assim a ordem de carga dos módulos não importa: se o `baikal_dmac` ainda não subiu, o driver segue pela CPU.
- **Quando devolver:** no `remove()` do `baikal-memory`. Enquanto o canal estiver pego, o `dmaengine` segura uma referência ao módulo `baikal_dmac` (`rmmod baikal_dmac` falha com "em uso"), o que é o comportamento seguro. Para liberar sem descarregar o `baikal-memory`, um parâmetro `use_dma=0` em runtime (§2.6) devolve o canal.

### 2.2 Endereços
- **Lado SPM:** `spm_dma = SPM_DMA_BASE + bar2_off`, com `SPM_DMA_BASE = 0xC0000000`.
- **Salvaguarda:** o deslocamento `+0x40000000` foi medido **neste console**, com o BAR2 PCI em `0x80000000`. No `probe`, se `pci_resource_start(BAR2) != 0x80000000`, o DMA fica **desligado** (log claro) e o driver segue pela CPU. Não generalizar sem prova em outro console.
- **Lado host:** um *bounce buffer* coerente de **1 MiB**, alocado com `dma_alloc_coherent()` **no `struct device` do DMAC** (`chan->device->dev`), porque é o DMAC que faz o acesso de barramento. Ele herda a máscara de 32 bits do DMAC, então o buffer fica abaixo de 4 GiB.
  - Alternativa descartada por ora: fixar as páginas do usuário (`pin_user_pages` + `dma_map_sg`), que evitaria uma cópia. O `copy_to_user` de um buffer em RAM custa pouco perto de 1,5 GB/s, e o bounce é muito mais simples. Reavaliar só se a medida mostrar que ele é o gargalo.

### 2.3 Divisão de cada `read()`/`write()` no BAR2
Para cada trecho dentro da janela do BAR2:
1. **Cabeça e cauda desalinhadas** (offset ou tamanho não múltiplos de 4) vão pela CPU, como hoje.
2. **Miolo alinhado** vai pelo DMA em pedaços de até 1 MiB (o tamanho do bounce), se for **≥ `dma_min`** (parâmetro, padrão 256 B; a 256 B o DMA já mediu 53 MB/s contra 4 MB/s da CPU).
3. Abaixo de `dma_min`, ou sem canal, tudo pela CPU.

**Leitura:** DMA SPM → bounce, espera a conclusão, `copy_to_user` do bounce.
**Escrita:** `copy_from_user` → bounce, DMA bounce → SPM, espera a conclusão. A checagem de `allow_write` continua no início do `write()`, **antes** de qualquer DMA: o DMA não vê o `allow_write`, então quem protege é o driver.

### 2.4 Espera e erro
- `dmaengine_submit()` + `dma_async_issue_pending()`; conclusão por callback (`callback_result`) que acorda uma `completion`.
- Espera com `wait_for_completion_timeout(3 s)`. É maior que o timeout de 2 s do próprio DMAC, para que normalmente seja o `baikal-dmac` a abortar e reportar.
- **Resultado `DMA_TRANS_ABORTED` ou timeout:** chama `dmaengine_terminate_sync()`, conta o erro, **refaz aquele pedaço pela CPU** (o dado continua correto) e desliga o DMA até a próxima recarga do módulo (`dma_disabled_reason` no sysfs). Um erro do DMAC aqui não é esperado; se acontecer, é sinal de que algo mudou e o fallback é o caminho seguro.
- Não chamar nada que durma com o `dev->lock` como spinlock: o `lock` já é `mutex`, então esperar a `completion` dentro dele é permitido. O mutex continua serializando todos os acessos, inclusive o bounce único.

### 2.5 Escopo da janela
**Fase A (este plano):** o DMA atende **só a janela que o driver já expõe** (4 MiB do BAR2). Mesma superfície de hoje; só muda a velocidade.
**Fase B (plano futuro, não agora):** o DMA não precisa de `ioremap`, então poderia expor os **256 MiB** reais do BAR2 sem mapear nada. Isso muda o layout de `/dev/baikal-memory` (hoje o BAR5 está em `0x500000`, logo depois da janela) e a política de escrita; fica para uma decisão separada.

### 2.6 Parâmetros e observabilidade
- `use_dma` (bool, padrão **0 na primeira tag de teste**, `1` depois de validado; gravável em runtime: `0` devolve o canal).
- `dma_min` (uint, bytes, padrão 256).
- sysfs (somente leitura): `dma_bytes_read`, `dma_bytes_written`, `cpu_bytes_read`, `cpu_bytes_written`, `dma_errors`, `dma_state` (`off` | `sem canal` | `ativo DMAC1` | `ativo DMAC2` | `desligado: <motivo>`).
- `dev_info` ao pegar/devolver o canal; `dev_err` em erro, com o `INT_FLAG` que o `baikal-dmac` já loga.

### 2.7 Kconfig
`CONFIG_BAIKAL_MEMORY` ganha `depends on DMA_ENGINE` (já é `=y` no config). **Sem** dependência de `BAIKAL_DMAC`: a ligação é só em runtime, pelo `dmaengine`. O config não muda (o símbolo já atende), então o ccache e o cache do ThinLTO continuam valendo.

---

## 3. Implementação (procedimento oficial do AGENTS.md)

1. Partir da árvore com os patches do build aplicados até o `baikal-dmac.patch` (o `baikal-memory.c` vem do `baikal-memory-fase2.patch`).
2. Editar `drivers/misc/baikal-memory.c` (+ a linha `depends on` no `drivers/misc/Kconfig`), incluindo a correção da lacuna no `baikal_mem_resolve()` (§1).
3. Compilar isolado: `make CC="ccache clang" LLVM=1 ARCH=x86_64 W=1 drivers/misc/baikal-memory.o`. Zero warnings.
4. Gerar `kernel/patches/baikal-memory-dma.patch` por `git diff` contra a base do passo 1 (nunca à mão).
5. Validar `git apply --check` num índice temporário, a partir do HEAD, na ordem do build (`baikal-memory-fase2` → `baikal-dmac` → `baikal-memory-dma`).
6. No `00-build-kernel-7.0.sh`: novo bloco `PATCH_BAIKAL_MEM_DMA` **depois** do `PATCH_BAIKAL_DMAC`, padrão `--check` + `exit 1`, e o nome na lista do preflight.
7. Build pelo script oficial → `install-modules-7.0.sh` → `rebuild-initramfs-7.0.sh` → `deploy-boot-7.0.sh`. Com o config congelado, o build deve levar poucos minutos.

Como `baikal-memory` e `baikal-dmac` são `=m`, uma iteração de correção pode recarregar só os módulos (sem trocar o bzImage), desde que ainda passe pelo build e pelo `install-modules` oficiais.

---

## 4. Riscos

| Risco | Mitigação |
|---|---|
| DMA escreve fora da janela ou ignorando `allow_write` | Checagem de `allow_write` e da janela no `write()` **antes** do DMA; o endereço DMA só é calculado a partir de um offset já validado pelo `baikal_mem_resolve()`. Teste dedicado na §5 |
| `+0x40000000` não valer em outro console | DMA só liga com o BAR2 PCI em `0x80000000`; senão CPU |
| Erro ou timeout do DMAC no meio de uma cópia | `terminate_sync`, refaz o pedaço pela CPU, desliga o DMA e registra o motivo |
| Conflito com o harness de RE (`baikal_dmac_test_spm`) | O harness exige `rmmod baikal_dmac`, que agora falha enquanto o `baikal-memory` segura o canal. Procedimento: `echo 0 > …/use_dma` (devolve o canal) ou `rmmod baikal_memory` antes |
| Corrida com o `mmap()` (CPU escrevendo direto no BAR2 enquanto o DMA lê) | Igual a hoje com a CPU: o driver não promete coerência entre `mmap` e `read/write` concorrentes. Documentar |
| `dmatest` ou outro cliente pegar o mesmo canal | O filtro aceita qualquer canal livre do `90dc`; se os dois estiverem em uso, segue pela CPU |
| Regressão do caminho pela CPU | O caminho pela CPU não muda; `use_dma=0` volta ao comportamento atual |

---

## 5. Testes ao vivo (uma sessão, nesta ordem)

Todos com o `baikal_dmac` carregado, salvo onde indicado. Escrita **só** na janela já usada: BAR2 `+0x200000` (offset de dispositivo `0x201000`), até 64 KiB, salvando o conteúdo antes e restaurando depois.

| # | Teste | Aceite |
|---|---|---|
| 1 | `use_dma=0`: `dd` de 1 MiB do BAR2 (offset de dispositivo `0x1000`) | Igual a hoje; vazão de referência (~4 MB/s) |
| 2 | `use_dma=1`: mesmo `dd` | **Idêntico** ao teste 1 (`cmp`), vazão ≥ 500 MB/s, `dma_state = ativo DMAC1` |
| 3 | Leituras desalinhadas: offsets `+1`, `+3`, `+0x1ffd`; tamanhos 1, 3, 255, 4097 B | Idênticas ao caminho pela CPU; contadores mostram cabeça/cauda pela CPU |
| 4 | Padrão aleatório de 64 KiB gravado com `allow_write=1` em `0x201000`, lido de volta | Readback = padrão; `dma_bytes_written` subiu |
| 5 | `allow_write=0`: tentar escrever | `-EPERM`, **nenhum** byte mudou (comparar antes/depois) |
| 6 | Escrita que atravessa o fim da janela | Igual a hoje: grava até o limite e devolve escrita **parcial** (o `dd` mostra menos bytes); nada além do limite muda |
| 6b | Leitura na lacuna `0x401000`–`0x4fffff` (bug da §1), só **depois** do patch | `read()` para no fim da janela (0 bytes ou fim de arquivo), **sem oops** |
| 7 | `rmmod baikal_dmac` com o canal pego | Falha "em uso"; `use_dma=0` → canal devolvido → `rmmod` passa → leituras seguem pela CPU |
| 8 | `baikal_memory` carregado **antes** do `baikal_dmac` | Começa pela CPU e passa a DMA quando o `baikal_dmac` sobe |
| 9 | Dois leitores simultâneos (`dd` em paralelo) por 30 s | Dados certos, sem erro, sem oops |
| 10 | Restaurar a janela de escrita e conferir | Igual ao conteúdo salvo |

Resultados no `test_history`, nesta seção e no BACKLOG.

### 5.1 Resultados ao vivo (2026-11-16, `test_history` 94–97)

Módulo da tag `20261116-dma-split` carregado de `/tmp` sobre o kernel do HD (a tag final `20261116-dma-final` só difere no padrão de `use_dma` e nos comentários; foi recarregada sem parâmetros e passou numa regressão curta). Todos os `dd` sem `iflag=direct`.

| # | Resultado | Veredito |
|---|---|---|
| 1 | CPU, 1 MiB: 0,258 s, **4,1 MB/s** | ✅ |
| 2 | DMA, 1 MiB: `cmp` == CPU; **547 a 624 MB/s** a quente (10 medidas, mediana ~617); a 1ª leitura após recarregar deu 402 MB/s (inclui alocar o bounce); 4 MiB: 887 a 924 MB/s; `dma_state = ativo DMAC1` | ✅ (≥ 500 MB/s a quente). O trecho é todo zero, então a igualdade é fraca; o conteúdo real foi provado no teste 4 |
| 3 | 13 leituras desalinhadas (+1, +3, +0x1ffd × 1, 3, 255, 4097 B, e +1 × 65535 B) idênticas ao padrão conhecido; contadores: cabeça/cauda pela CPU, miolo pelo DMA (+1 × 4097: cpu 5 / dma 4092) | ✅ — **exigiu código novo** (divisão do §2.3): antes tudo desalinhado ia inteiro pela CPU |
| 4 | 64 KiB aleatórios por DMA em `0x201000`; readback CPU == DMA == padrão; `dma_w+65536`. Escrita desalinhada (4097 B em +1) também correta, bytes vizinhos preservados | ✅ |
| 5 | `allow_write=0`: `dd: Operation not permitted`; janela com hash idêntico antes/depois, com o DMA ativo | ✅ |
| 6 | 4096 B a partir de `0x400800`: gravou **2048 B** (escrita parcial, EPERM no resto), conteúdo conferido | ✅ O hash da BAR5 não serve (ela tem dados vivos: 5 leituras sem escrita, 5 hashes distintos). Controle pareado depois (`test_history` 100): 10 rodadas sem escrita × 10 com escrita, com snapshots da BAR5 antes e depois de cada uma: **0 offsets** mudam em ≥ 7 rodadas com escrita e em nenhuma sem escrita; média de ~24 bytes mudados por rodada sem escrita contra ~14 com escrita. Sem evidência de efeito (não é prova formal); o código também não tem caminho de escrita fora do BAR2 |
| 6b | Leitura na lacuna: **0 bytes, sem oops**; leitura de 8192 B a partir de `0x400800` devolve só 2048 B | ✅ — a versão antiga devolvia `-ENODEV`; agora a lacuna lê como fim de dados (código novo) |
| 7 | `rmmod baikal_dmac` com canal: "in use"; `echo 0 > dma/use_dma` devolve o canal (`sem canal`, refcnt 0); `rmmod` passa; leitura segue pela CPU (4 MB/s) | ✅ (o canal é devolvido pelo atributo sysfs `dma/use_dma`, não pelo parâmetro de módulo) |
| 8 | `baikal_memory` antes do `baikal_dmac`: funciona pela CPU sem erro (**aceite 3**); após o `baikal_dmac` subir, passa ao DMA sozinho em até ~1 s (backoff de 1 s) | ✅ — **exigiu código novo** (`baikal_dma_try_enable`): antes `echo 1 > use_dma` não fazia nada se `use_dma` já fosse 1 |
| 9 | 2 leitores por 30 s: 8094 leituras de 64 KiB (530 448 384 B por DMA), 0 divergentes, `err=0` | ✅ |
| 10 | Janela (64 KiB) e fim de janela (2 KiB) restaurados e conferidos == originais (que eram todo zero) | ✅ |

**Critérios de aceite (§ topo):** 1 ✅ (≥ 500 MB/s a quente, idêntico à CPU), 2 ✅ (`-EPERM` também no caminho DMA), 3 ✅ (funciona sem o `baikal_dmac`), 4 ✅ (nenhum oops nem erro do DMAC no `dmesg` em toda a bateria).

**Mudanças feitas no patch durante o fechamento** (`kernel/patches/baikal-memory-dma.patch`): `dma_chunk` calculado só depois de alocar o bounce (causa do `len=0`); divisão cabeça/miolo/cauda; leitura na lacuna devolve fim de dados; reaquisição do canal sob demanda; `dma_state` mostra `ativo DMAC1`/`DMAC2`; `use_dma` padrão `1`. Compila com `W=1` sem avisos.

**Desvios que continuam em relação ao desenho:** (a) o erro de DMA desliga o DMA até recarregar o módulo e o `dma_state` mostra `desligado: erro anterior` (sem o motivo detalhado do §2.6); (b) o tempo de espera no `baikal_dma_do_transfer` é de 3 s como no §2.4, mas **não há teste de erro induzido** do DMAC (o fallback por erro nunca foi exercitado ao vivo); (c) o `baikal-memory-dma-v2.patch`, uma alternativa **abandonada** que ainda tinha o bug do `dma_chunk`, foi removido do repositório.

**Armadilhas de teste:** `dd of=-` NÃO escreve na saída padrão (cria um arquivo chamado `-`); para hash, omita `of=`. Restaurar zeros com `head | dd bs=64k count=1` grava só parte (o `dd` lê o pipe uma vez): use arquivo. `allow_write` é `0444` (só muda recarregando o módulo).

---

## 6. Fora de escopo
- Fase B (256 MiB pelo DMA, novo layout do `/dev/baikal-memory`).
- IRQ do DMAC2 (pendência antiga do `baikal-dmac`).
- `mmap()` com DMA.
- Swap/zram sobre a SPM.

---

## 🐛 Bug `prep_dma_memcpy falhou (len=0)` — ✅ RESOLVIDO (2026-11-16)

**Sintoma:** no primeiro uso de DMA, `dmaengine_prep_dma_memcpy` falhava com `len=0` logo depois de o bounce de 1 MiB ser alocado, e o erro desligava o DMA para sempre.

**Causa (confirmada em hardware):** `dma_chunk = min_t(size_t, chunk, dev->dma_bounce_size)` era calculado **antes** de `baikal_dma_alloc_bounce()`, e `dma_bounce_size` só recebe valor dentro dessa função (0 até lá). A hipótese antiga desta seção (transição BAR0→BAR2, `total_read`) estava errada: o cálculo não depende de BAR.

**Correção:** `dma_chunk` é calculado depois da alocação, nas duas funções (commit `c5074ad`). Detalhes e medidas: `AGENTS.md` (seção do bug `len=0`) e §5.1 acima.
