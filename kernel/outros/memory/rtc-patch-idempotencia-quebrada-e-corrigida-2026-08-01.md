---
name: rtc-patch-idempotencia-quebrada-e-corrigida-2026-08-01
description: ps4-icc-rtc-wrapper.patch perdeu o arquivo drivers/rtc/rtc-ps4-icc.c num commit anterior, quebrando reprodutibilidade; corrigido e revalidado.
metadata:
  type: project
---

## O que aconteceu

O commit `7d59131` ("fix(rtc): update rtc-ps4-icc patch with software time tracking and ICC
context save/load", 2026-08-01 18:25) reescreveu `distros/arch_minimal_v2/patches/ps4-icc-rtc-wrapper.patch`
mas **removeu sem querer o hunk que criava `drivers/rtc/rtc-ps4-icc.c`** (era um `--- /dev/null`
de 180 linhas presente no commit anterior `135413c`). O `drivers/rtc/Makefile`/`Kconfig` continuaram
referenciando `rtc-ps4-icc.o`/`CONFIG_RTC_DRV_PS4_ICC`, mas o `.c` correspondente não existia mais
em nenhum patch nem no repositório.

O build de `20260801-sata-func7-fix` só funcionou porque `drivers/rtc/rtc-ps4-icc.c` (e também
`drivers/ps4/ps4-icc-debug.c`) sobraram fisicamente **untracked** na árvore efêmera
`/mnt/hdauxiliar/temp/kernel_build_7.0` de uma sessão manual anterior, e o `git clean -fdx` daquele
build específico não os removeu (caminho exato ainda não determinado — não investigado a fundo,
não é mais relevante já que a árvore foi limpa e o patch corrigido). Um clone/build 100% do zero
teria falhado a compilar (`rtc-ps4-icc.o` referenciado sem `.c` correspondente).

Isso é exatamente o padrão do incidente de SATA de 2026-08-01 (ver
`memory/regressao-sata-2026-08-01-diagnostico-e-solucao.md`), agora no RTC — mudança real só
sobrevivendo por acidente na árvore efêmera, não capturada em patch.

## Achado extra: driver é funcionalmente decorativo

Lendo `drivers/rtc/rtc-ps4-icc.c`: `ps4_rtc_read_time()` chama `ps4_icc_rtc_cmd(2, 0x0c, ...)`
("load context") mas **descarta o valor retornado** — só usa pra logar warning em caso de falha.
A hora reportada vem inteiramente de `sc->base_time + jiffies decorridos desde o boot`, e
`base_time` começa em 0 no `probe()`. Por isso o boot sempre loga
`"setting system clock to 1970-01-01T00:00:00 UTC (0)"` — não existe carregamento real da hora
salva via ICC, apesar do nome dar a entender que existe. Testado ao vivo 2026-08-01: `since_epoch`
avança corretamente em tempo real (contador funciona), mas **não sobrevive a reboot** de forma
alguma hoje — nem por bug de hardware/ICC, mas porque o valor de retorno do `ps4_icc_rtc_cmd` de
load nunca é usado para inicializar `base_time`.

Não corrigido nesta rodada (fora de escopo — só a idempotência foi resolvida agora). Se a intenção
é RTC persistente de verdade, o próximo passo é decodificar o formato do reply de
`ps4_icc_rtc_cmd(2, 0x0c, ...)` e usar o valor pra inicializar `base_time` no `probe()`.

## Correção aplicada (idempotência)

1. Reconstruído `patches/ps4-icc-rtc-wrapper.patch` via `git diff HEAD` real (nunca escrito à mão),
   a partir do conteúdo já presente e funcional na árvore efêmera, **staged com
   `git add drivers/rtc/rtc-ps4-icc.c`** antes do diff (arquivo estava untracked, `git diff HEAD`
   sozinho não captura arquivos novos não staged).
2. **Removido do escopo do patch**: o hunk `drivers/ps4/Makefile` (`+obj-y += ps4-icc-debug.o`) e
   o arquivo `drivers/ps4/ps4-icc-debug.c` inteiro. Achado bônus: esses dois já pertencem a
   `patches/ps4-icc-proc-debug.patch` (aplicado só em build frio, `if [ ! -f drivers/net/ethernet/sony/mts.c]`)
   — o patch RTC estava duplicando o mesmo hunk de Makefile. Em build frio real (sem `mts.c`
   presente), os dois patches aplicando o mesmo `+obj-y += ps4-icc-debug.o` teriam conflito de
   `git apply --check` (contexto já mudado pelo primeiro patch). Nunca acontecia porque todo build
   recente já tinha `mts.c` presente (path incremental), mascarando o bug. Corrigido removendo a
   duplicata do patch RTC — RTC não depende de `ps4-icc-debug.c` para nada.
3. Validado do zero, em sequência, a partir de árvore pristina (`git reset --hard origin/$BRANCH` +
   `git clean -fdx`):
   - `git apply --check patches/ps4-icc-rtc-wrapper.patch` → OK
   - `git apply` real → OK
   - Compilação isolada: `make CC="ccache clang" LLVM=1 ARCH=x86_64 drivers/ps4/ps4-bpcie-icc.o drivers/rtc/rtc-ps4-icc.o` → sem erros
   - `nm`: `ps4_icc_rtc_cmd` aparece `T` (definido) em `ps4-bpcie-icc.o` e `U` (resolvido) em `rtc-ps4-icc.o`
4. Árvore efêmera devolvida ao estado limpo (`git reset --hard` + `git clean -fdx`) — nada
   "guardado" nela, tudo o que importa está no patch commitado.

## Status

- Patch corrigido e commitado no repositório principal.
- **Não validado em hardware ainda** — o binário efetivamente rodando no PS4 agora (tag
  `20260801-sata-func7-fix`) já usa o conteúdo correto (era o mesmo conteúdo, só não estava
  capturado em patch), então não é regressão — mas a persistência real de hora entre boots
  continua não implementada (ver "Achado extra" acima), independente da idempotência estar corrigida.
