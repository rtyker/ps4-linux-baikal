# Plano — swap na SPM/DDR3 do Baikal, movido por DMA

**Data:** 2026-11-16 · **Status:** 🟡 Implementado e validado ao vivo com o módulo compilado fora da árvore. O módulo do build oficial (tag `20261116-spm-swap`) e o teste de região (`spm_probe_region`) **ainda não foram validados no console** (o PS4 estava desligado). Nada disso está gravado no HD.

**Origem:** o patch do Debarshi (PS4 Pro/Belize) expõe o DDR3 do southbridge como disco de swap e usa DMA no lugar da cópia pela CPU (`WRITEUP_DEBARSHI_DDR3_2026-11.md`). Este plano faz o mesmo no nosso console (PS4 Pro com Baikal), em cima do que o plano `PLANO_DMA_SPM_DDR3` já provou: o DMAC `00:14.5` lê e escreve a SPM em `0xC0000000 + off`.

---

## 1. O que a SPM realmente oferece (medido em 2026-11-16)

Varredura **somente leitura** pelo DMA (`others/rea/dma/harness/baikal_spm_scan/`), de 1 MiB em 1 MiB, com o buffer envenenado (`0xA5`) antes de cada leitura para distinguir "zeros de verdade" de "o DMA não escreveu":

| Região | Conteúdo | Observação |
|---|---|---|
| 0 a 187 MiB (188 MiB) | tudo zero | memória que responde |
| 188 MiB a 1023 MiB (836 MiB) | ~99,997% `0xFF` (20–90 bytes diferentes por MiB, em posições que mudam) | é o que se lê quando nada responde; 0 dos 768 blocos comparados a 256 MiB de distância são iguais, então **não é aliasing** |

- A **CPU (BAR2) e o DMA concordam** nos limites (blocos 0, 100, 187: zero; 188, 189, 200, 255, 256, 257, 512: `0xFF`).
- **Escrita e leitura de volta por DMA** (4 KiB no início e no fim de 8 blocos, de 4 a 187, só onde já era zero, restaurando zeros): **16 de 16 OK**, inclusive o último 4 KiB do bloco 187. Repetido no **DMAC2** (`dma0chan1`), com o mesmo resultado.
- Nenhum erro do DMAC em 1024 MiB lidos; a varredura inteira leva ~1 s.

**Capacidade utilizável: 188 MiB**, não 256 MB nem 1 GiB. Uma sessão antiga mediu zeros até 256 MB; as duas medições discordam e a causa não foi explicada (o usuário levantou que pode ser parâmetro do payload). **Por isso o driver confere a região ao carregar** (§3).

## 2. Desenho

Novo módulo `baikal-spm-blk` (`drivers/block/baikal-spm-blk.c`, patch `kernel/patches/baikal-spm-blk.patch`, `CONFIG_BAIKAL_SPM_BLK=m`): um disco **baseado em `bio`** (como `brd` e `zram`) chamado `/dev/baikal_spm0`.

- **Região:** `offset_mb=4` e `size_mb=180` por padrão (4 a 184 MiB). Os primeiros 4 MiB ficam para o `/dev/baikal-memory`. O driver **recusa** `offset_mb + size_mb > 188`.
- **Movimento de dados:** `submit_bio` junta até 1 MiB num buffer coerente (que o DMAC alcança), faz **uma** transferência DMA por pedaço e termina o `bio` antes de voltar. Leitura: DMA da SPM para o buffer e cópia para as páginas; escrita: o inverso.
- **Swap exige progresso com pouca memória:** nenhum `kmalloc` no caminho de I/O (os buffers são alocados no carregamento). O `baikal-dmac` aloca descritores com `GFP_NOWAIT`, que **pode falhar**; isso, um timeout ou um aborto do DMAC só manda **aquele pedaço** para uma cópia pela CPU (`memcpy_toio`/`memcpy_fromio` pela BAR2). Só 8 erros duros (aborto/timeout, **não** falta de memória) desligam o DMA até recarregar o módulo.
- **O aborto do DMAC só chega por `callback_result`** (lição do `baikal-memory`, `test_history` 101): o driver já nasce lendo o resultado.
- **Canal DMA tardio:** se o `baikal_dmac` ainda não subiu, o disco funciona pela CPU e uma rotina agendada (fora do caminho de I/O) pega o canal depois. Ele pega o primeiro livre; com o `baikal-memory` segurando o DMAC1, pega o DMAC2 (validado para a SPM).
- **Contadores** em `/sys/block/baikal_spm0/`: `dma_bytes`, `cpu_bytes`, `dma_fallbacks`, `dma_errors`, `state`.
- **Uso:** `mkswap /dev/baikal_spm0 && swapon -p 50 /dev/baikal_spm0`. Empacotado em `distro/baikal-spm-swap.service` + `distro/baikal-spm-swap.default` + `distro/scripts/install-spm-swap.sh`. **Prioridade padrão 50**, abaixo do zram (100): a SPM só recebe o transbordo. Acima de 100 ela seria usada primeiro e pouparia RAM, mas pagina mais devagar que o zram em páginas isoladas.

## 3. Confiar na memória só depois de conferir

Se a SPM responder menos do que o configurado, páginas de swap seriam gravadas em nada e voltariam como `0xFF`, corrompendo processos. `spm_probe_region()` roda ao carregar: em 5 pontos da região (início, 1/4, 1/2, 3/4, fim) grava 64 bytes com `0xA5` e `0x5A`, relê, restaura o original e **recusa o dispositivo** (`-ENODEV`) se qualquer ponto não devolver o que foi escrito. *(Escrito depois dos testes ao vivo abaixo: precisa de teste no console.)*

## 4. Resultados ao vivo (2026-11-16, módulo compilado fora da árvore; `test_history` 104–106)

**Dispositivo de bloco** (`blk_test.sh`, 8 PASS / 0 FAIL): `/dev/baikal_spm0` com 180 MiB, DMA ativo no `dma0chan1`.

| Teste | Resultado |
|---|---|
| T1 integridade `O_DIRECT`, 10 combinações de setor e tamanho (inclui setores desalinhados e 3–4 MiB, maiores que o buffer de 1 MiB) | idênticas |
| T2 dispositivo inteiro (180 MiB) com dado aleatório | gravado e relido **byte a byte igual**; escrita 553 MB/s, leitura 591 MB/s |
| T3 caminho com cache de página (gravar, `sync`, limpar o cache, ler) | iguais |
| T4 vazão `O_DIRECT` 64 MiB | escrita 649 MB/s, leitura **1,0 GB/s**; leitura em blocos de **4 KiB: 112 MB/s** |
| T5 modo só-CPU (`use_dma=0`) | correto, contadores só de CPU |
| T6 escrever depois do fim | recusado |

**Swap de verdade** (`swap_test.sh`, 10 PASS / 0 FAIL). Processos confinados por cgroup (`MemoryMax`) para forçar a paginação **sem esgotar a RAM do console**; a SPM em prioridade 200 só durante o teste; cada bloco de 1 MiB conferido por CRC32 depois de voltar do swap:

| Teste | Resultado |
|---|---|
| S1: 1 processo, 48 MiB de RAM, 140 MiB de dados, 3 passadas aleatórias | `pswpout` 37 073 páginas (**144 MiB para fora**), `pswpin` 103 877 (**405 MiB de volta**), **0 blocos corrompidos**, tudo pelo DMA, sem erro nem fallback |
| S2: 3 processos concorrentes (40 MiB cada, 16 MiB de RAM cada) | 0 blocos corrompidos |
| S3: swap com o DMA desligado | correto; 30 MiB lidos em 6,85 s (~4,4 MB/s), contra 140 MiB em 1,58 s com DMA (~88 MB/s, **~20× mais rápido**) |
| `swapoff`, `rmmod`, dispositivo zerado e conferido | sem aviso do kernel (nada de `hung task`, `oom` ou `Call Trace` novo) |

## 5. Limites e o que NÃO foi feito

- **188 MiB é pouco.** Com 6,9 GB de RAM e o zram de 3,4 GB, a SPM só importa sob pressão real de memória. O ganho é de **latência do transbordo**, não de capacidade. Usar mais exigiria a SPM responder além de 188 MiB (ver §1).
- **Não foi feito:** zswap/compressão na frente da SPM (o Debarshi usa zswap LZ4; aqui o zswap está desligado e o zram já comprime), prefetch, e múltiplas filas (`blk-mq`). O disco é serializado por um mutex e um buffer único.
- **Pendente:** validar no console o módulo do build oficial e o teste de região; gravar no HD (`install-modules-7.0.sh` + `install-spm-swap.sh` + `deploy-boot-7.0.sh`); teste de carga mais longo (horas) e com o `baikal-memory` ativo ao mesmo tempo.
- **Risco conhecido:** escrever em memória cujo tamanho varia entre boots. Mitigado por `spm_probe_region`, que cobre 5 pontos de 64 bytes, **não** a região inteira.
