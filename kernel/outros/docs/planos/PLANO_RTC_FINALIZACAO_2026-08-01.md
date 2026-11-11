# Plano: Finalizar RTC via ICC — de "decorativo" a persistente de verdade

> ⏸️ **PAUSADO em 2026-08-01 no Passo 1.** `/proc/iomem` ao vivo confirmou que `0x05180000`/
> `0x05140000` caem dentro de `System RAM` ativa (mesmo bloco onde o próprio kernel Linux tem
> código/dados carregados) — não uma região reservada. Usuário decidiu não assumir o risco de
> `ioremap` sobre RAM em uso. Não retomar sem novo direcionamento. Ver
> `memory/rtc-mmio-pausado-risco-system-ram-2026-08-01.md`.

## Contexto

O driver `drivers/rtc/rtc-ps4-icc.c` está registrado, carrega, e responde em `/dev/rtc0`, mas hoje é
**funcionalmente decorativo**: `ps4_rtc_read_time()` chama `ps4_icc_rtc_cmd(2, 0x0c, ...)` ("load
context" via ICC) mas descarta o valor de retorno — a hora reportada vem de um contador de software
(`base_time + jiffies decorridos`) que sempre nasce zerado no boot. Confirmado ao vivo em
2026-08-01: `dmesg` sempre loga `"setting system clock to 1970-01-01T00:00:00 UTC (0)"`, e a hora
nunca sobrevive a um reboot.

Esse comportamento é uma **regressão**, não a implementação original: o commit `135413c`
(2026-07-31) continha uma versão completa via MMIO real (`readq`/`writeq` em `0x5180000`/
`0x5140000`, endereços físicos do RTC do SoC Baikal confirmados por engenharia reversa do kernel
Orbis original — `rtc.c`, não o `rtc_mvl.c` read-only). O commit `7d59131` (2026-08-01) substituiu
essa lógica pela versão jiffies sem motivo documentado, e essa foi a versão restaurada (por
idempotência do patch, não por escolha de design) no commit mais recente `e40154e`.

A RE do protocolo está validada duas vezes (dump ARM do SC original + dump x86 do kernel 12.52) —
alta confiança nos comandos ICC e endereços MMIO. Nunca houve um teste real em hardware:
qualquer entrada anterior do `BACKLOG.md` dizendo "RTC validado ao vivo" foi corrigida como falsa em
2026-07-31.

**Único risco real e não verificado:** `0x5180000`/`0x5140000` (~84-85 MB) são endereços físicos
crus do SoC, fora da janela alta de BARs PCI (`0xc0000000+`) onde ficam todos os outros
dispositivos Baikal já mapeados neste projeto. Não há PCI function associada. Se essa faixa
colidir com RAM que o Linux já usa (heap do kernel, etc.), um `ioremap` direto pode falhar
"seguro" (recusado pelo kernel) ou, em cenário pior, mapear sobre memória já em uso. **Isso precisa
ser checado em `/proc/iomem` no PS4 real ANTES de qualquer rebuild** — é o gate que decide se o
caminho abaixo é direto ou precisa de um passo extra (reserva de memória).

## Passo 1 — Checar `/proc/iomem` no PS4 real (bloqueador, decide o caminho do Passo 3)

Via SSH (`sshpass -p ps4 ssh root@192.168.6.128 "cat /proc/iomem"`), procurar a faixa
`0x05180000`-`0x05180007` e `0x05140000`-`0x05140007` (ou a região de ~1 MB ao redor, para ver o
que o Linux já reivindicou ali).

- **Se a faixa aparecer como `System RAM`**: colisão real. Parar e reportar ao usuário — não seguir
  para o Passo 3 sem decidir juntos uma estratégia (ex: reservar a região cedo via `memblock_reserve`/
  cmdline `memmap=`, ou investigar se o endereço físico visto pelo Orbis mapeia para outro endereço
  no espaço de memória do Linux x86 — os dois SOs podem ter mapas de memória física diferentes
  mesmo no mesmo hardware).
- **Se a faixa aparecer como `Reserved`, não aparecer (buraco no mapa), ou aparecer com um nome de
  dispositivo genérico não conflitante**: seguro para `ioremap` direto, seguir Passo 3 sem alterações.

## Passo 2 — Decisão de design: reintroduzir MMIO, remover contador jiffies

Reverter `ps4_rtc_read_time()`/`ps4_rtc_set_time()` para a versão MMIO real (recuperável de
`git show 135413c:distros/arch_minimal_v2/patches/ps4-icc-rtc-wrapper.patch`), com duas melhorias
sobre aquela versão (não reinvenção — só robustez básica que a versão original não tinha):

1. **Sentinela de "nunca configurado"**: a RE de `rtc_load_context` (`dc57f340`) usa a constante
   `0x7fffffffffffffff` como valor de leitura inválida/não inicializada. Se `readq(mmio_read)`
   retornar `0` ou esse sentinela, `read_time()` deve retornar `-EINVAL` (padrão do subsistema RTC
   do Linux para "relógio nunca foi configurado", mesmo comportamento de `rtc_cmos` quando a
   bateria morre) em vez de reportar 1970-01-01 como se fosse uma leitura válida.
2. Manter o `spin_lock`/`dev_warn_ratelimited` que a versão jiffies introduziu, mas usados só para
   proteger o acesso ao MMIO (não mais para um contador de software) — remove `base_time`/
   `base_jiffies`/`jiffies.h` do struct e do arquivo inteiro.

`ps4_icc_rtc_cmd(2, 0x0c/0x0b, ...)` continuam sendo chamados (load/save context), pois é isso que
o Orbis faz antes/depois de tocar no MMIO — mas seu retorno continua sendo best-effort (log warning
em falha, não aborta a operação), já que a fonte de verdade real da hora é o MMIO, não o reply ICC
(confirmado pela RE: o Orbis só usa o reply do load-context como uma flag de "contexto já existia",
não como o valor da hora em si).

## Passo 3 — Implementação seguindo a doutrina de idempotência do projeto (AGENTS.md)

Mesma sequência já usada nos patches de SATA/MTS nesta sessão — não pular etapas:

1. Na árvore efêmera `/mnt/hdauxiliar/temp/kernel_build_7.0`, resetar para pristino
   (`git reset --hard origin/baikal/7.0.8-Stable && git clean -fdx`), aplicar o patch RTC atual já
   commitado (`git apply patches/ps4-icc-rtc-wrapper.patch`) para partir do estado correto de
   Kconfig/Makefile/wrapper (que já estão certos, não mudam neste plano).
2. Editar `drivers/rtc/rtc-ps4-icc.c` diretamente na árvore com a lógica MMIO + sentinela do Passo 2.
3. Compilar isolado: `make CC="ccache clang" LLVM=1 ARCH=x86_64 drivers/rtc/rtc-ps4-icc.o` — deve
   compilar limpo antes de qualquer outra coisa.
4. Gerar o patch **real** via `git diff` (nunca escrito à mão): como o arquivo `.c` fica untracked
   depois do `git apply` (é um new-file patch, não um commit), usar
   `git add drivers/rtc/rtc-ps4-icc.c` antes de `git diff HEAD -- drivers/ps4/aeolia.h drivers/ps4/baikal.h drivers/ps4/ps4-bpcie-icc.c drivers/rtc/Kconfig drivers/rtc/Makefile drivers/rtc/rtc-ps4-icc.c > novo-patch`
   (mesmo escopo de arquivos do patch atual — sem `drivers/ps4/Makefile`/`ps4-icc-debug.c`, que
   pertencem ao patch GBE, conforme já corrigido nesta sessão).
5. Resetar a árvore de novo (`git reset --hard` + `git clean -fdx`), `git apply --check` do novo
   patch a partir de pristino — só prossegue se passar limpo.
6. Aplicar de verdade, recompilar isolado (`drivers/ps4/ps4-bpcie-icc.o drivers/rtc/rtc-ps4-icc.o`)
   confirmando de novo sem erros, `nm` para confirmar resolução do símbolo `ps4_icc_rtc_cmd`.
7. Substituir `distros/arch_minimal_v2/patches/ps4-icc-rtc-wrapper.patch` no repositório principal
   pelo novo conteúdo. Resetar a árvore efêmera outra vez (descartável, nada fica guardado nela).

## Passo 4 — Build oficial e deploy

Rodar a sequência oficial de build (`00-build-kernel-7.0.sh <TAG>`, ex:
`20260801-rtc-mmio-real`) — só depois do Passo 3 validado. Deploy com `deploy-boot-7.0.sh <TAG>`
(boot-only, sem mudança de rootfs/initramfs necessária).

## Passo 5 — Validação em hardware real (o teste que nunca foi feito)

1. Após boot, checar `dmesg | grep -i rtc` — não deve mais aparecer
   `"setting system clock to 1970-01-01"` como comportamento normal (só se o RTC de fato nunca foi
   configurado, que é o estado esperado na primeira vez).
2. `date -s "<hora atual real>"` seguido de `hwclock -w` (grava no RTC via `set_time` → MMIO write
   + ICC save context).
3. `hwclock -r` ou `cat /sys/class/rtc/rtc0/since_epoch` para confirmar a leitura imediata bate.
4. **Teste decisivo**: reboot completo (`reboot` ou power-cycle) e checar, ANTES de qualquer
   `date -s` manual ou NTP, se `dmesg`/`date`/`hwclock -r` já mostram a hora correta (ou próxima,
   considerando o tempo de boot) — isso é o que hoje falha (sempre volta pra epoch 0).
5. Se falhar mesmo com a lógica MMIO: os candidatos mais prováveis de causa raiz, em ordem de
   probabilidade, são (a) o `ioremap` de fato colidiu com algo e a leitura retorna lixo/panic —
   volta pro Passo 1; (b) o hardware RTC físico do Baikal não tem bateria/capacitor funcional para
   manter o registrador durante desligamento total (S5) — nesse caso o comportamento é uma
   limitação de hardware, não de driver, e o item vira "não solucionável em software" até prova em
   contrário.

## Critério de "pronto"

- `/proc/iomem` checado, sem colisão de `System RAM` nos endereços do RTC (ou estratégia de
  mitigação decidida com o usuário se houver colisão).
- Patch reconstruído, validado do zero (`git apply --check` + compilação isolada) a partir de árvore
  pristina, igual ao rigor já aplicado a SATA/MTS nesta sessão.
- Commitado no repositório principal.
- Build oficial + deploy feitos.
- **Teste de reboot real** (Passo 5.4) executado e resultado registrado em `memory/` — positivo
  (hora persiste) ou negativo com causa raiz identificada (limitação de hardware vs bug de driver).

## Fora de escopo desta rodada

- Decompilar as 5 funções ainda pendentes (`dc839e40`, `dc839d90`, `dc6b1a20`, `dc6b1b80`,
  `dc797090`) — não são necessárias para a implementação Linux (equivalentes triviais já
  identificados: `readq`/`writeq` e `bpcie_icc_cmd`, que já são usados).
- Suporte a alarme (`read_alarm`/`set_alarm`) além do que já existe — já segue a RE
  (`major=4 minor=0x50`), não identificada nenhuma lacuna aí.
- Investigar se há bateria/capacitor de backup físico no RTC do Baikal (só relevante se o Passo 5
  falhar e apontar para limitação de hardware).
