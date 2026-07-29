# Plano: kexec nativo do Linux para warm-reboot entre kernels no PS4 (Baikal)

## ⏸️ SESSÃO PAUSADA 2026-07-28 (fim de tarde) — RETOMAR DAQUI

**Estado físico do PS4 ao pausar:** kernel travado pelo `test-11-initcall-debug` (boot
novo parou em ~127.7s de kernel time, 6 min de silêncio total confirmados — ping e SSH
mortos). Usuário precisará fazer novo power cycle físico quando retomar — **não presumir
que o PS4 já está num estado limpo/conhecido na próxima sessão; confirmar com o usuário
antes de qualquer SSH.**

**Onde exatamente paramos:** 4 testes de diagnóstico realizados nesta sessão
(2026-07-28), a localização do travamento ficou muito mais precisa:

1. `setpci` isolado no bit MSI-enable do xHCI, sem unbind — quebrou o disco (erro real de
   journal EXT4 aborted em `/dev/sdb2`, confirmado por foto da tela).
2. (sessão anterior) `unbind` completo do driver `xhci_aeolia` — quebrou o disco do mesmo
   jeito.
3. `pci=nomsi` no bootargs do kernel-alvo — travou ainda MAIS CEDO (13.8s), com 3
   dispositivos PCI (incl. xHCI) em `deferred probe pending` — refuta "só faltava
   desabilitar MSI".
4. **`initcall_debug` no bootargs do kernel-alvo (sem `nomsi`) — achado mais preciso até
   agora:** o driver `mts` (Ethernet) termina seu próprio `initcall` com sucesso
   (`mts_driver_init ... returned 0`, roda como módulo via worker udev PID 294), registra
   `eth0`, e **nenhum `calling X+0x0/...` posterior aparece no log** — ou seja, o
   travamento NÃO é dentro de um driver/initcall síncrono. É algo fora do
   `do_one_initcall()`, quase certamente o worker do `systemd-udevd` travando ao processar
   o uevent do PRÓXIMO dispositivo (muito provável: xHCI `0000:00:14.7`, coerente com o
   achado do teste 3).

**Bônus não relacionado ao kexec, mas relevante para outros bugs abertos do projeto:**
esse teste capturou o log verboso do `mts.ko` com um comando ICC `major=4,minor=0x38`
("GBE power-on") já confirmado pelo driver — diferente do `major=5,minor=0x41` já
descartado como controle de power da GBE — registrado como pista nova para o bug de RX
Ethernet (não investigada a fundo ainda). Também foi capturado, numa sessão de power-cycle
de rotina no meio do dia, o boot completo do payload Orbis original (não-kexec) com um
handshake ICC de shutdown bem mais rico que o do driver Linux `poweroff -f` — relevante
para o bug pendente de S5. Ver `memory/orbis-payload-sequencia-boot-capturada-live-2026-07-28.md`.

**Próximo passo ao retomar:**
- Bootargs `udev.log_level=debug`/`systemd.log_level=debug` no kernel-alvo, para tentar
  capturar qual uevent específico o `systemd-udevd` está processando no exato momento do
  travamento — mais direto que inferir só pela ordem PCI.
- `pci=noaer` ou outros bootargs PCI mais seletivos (menos agressivos que `nomsi` total)
  no kernel-alvo, para tentar isolar sem quebrar o boot inteiro.
- Avaliar com o usuário se vale a pena continuar essa investigação ou se o objetivo
  original (acelerar bootcycles pra debugar o bug de S5/poweroff) deve ser abandonado por
  ora — o ciclo continua sendo power-cycle físico + payload Orbis + boot Linux normal.

**Arquivos de teste já prontos (não precisam ser recriados):**
- `distros/arch_minimal_v2/boot_referencia/bootargs-7.0-20260727-current-uart-keep-bootcon.txt`
- `distros/arch_minimal_v2/boot_referencia/bootargs-7.0-s5-poweroff-fix-20260725-v5-uart-keep-bootcon.txt`
- Ambos já foram copiados para `/mnt/boot` no PS4 também (mas confirmar que sobreviveram
  ao power cycle / ainda estão lá, já que ficam no HD USB `/dev/sdb1`, não deveriam ter
  sumido).

**Detalhe técnico completo de todos os testes de hoje (test-01 a test-08):**
`memory/kexec-nativo-mecanismo-funciona-mas-v5-trava-pos-console-handoff-2026-07-27.md`
(este arquivo passou por duas correções de diagnóstico ao longo do dia — ler o arquivo
inteiro, não só o topo, para entender a evolução do entendimento).

## Contexto

Cada iteração de teste de kernel hoje custa um ciclo completo: reboot → volta
ao firmware oficial da Sony → boot do disco `HEN.AIO` (às vezes falha com
erro de R/W, já registrado como pendência recorrente no `BACKLOG.md`) →
payload reinjeta o exploit `kexec` customizado do Orbis (não é o kexec do
Linux) → carrega o Linux de novo. Isso está bloqueando a velocidade de
depuração do bug de S5/poweroff (kernel `s5-poweroff-fix-20260725-v5`), que
já foi testado ao vivo mas ainda não teve seu ciclo de iteração acelerado.

Objetivo: usar o **`kexec` nativo do Linux** (kexec-tools, `kexec_load()` do
kernel), chamado de DENTRO do Linux já rodando no PS4, para trocar de kernel
em RAM sem passar de novo pelo firmware Sony/disco/payload — um "warm
reboot" que deve reduzir drasticamente o custo de cada iteração de teste.

## Descobertas que embasam o plano

- **O kernel já suporta:** `CONFIG_KEXEC=y`, `CONFIG_KEXEC_CORE=y`,
  `CONFIG_KEXEC_FILE=y` confirmados nos `config-7.0-*` existentes. Nada a
  mudar no `.config`.
- **Falta `kexec-tools` no rootfs.** Não está em
  `distros/arch_minimal_v2/pkglist.x86_64.txt` (confirmado, zero entradas
  `kexec*`).
- **BOOT (`/dev/sdb1`, vfat) não é automontada dentro do Linux rodando** —
  hoje só é acessada pelo host via `02-burn-image-7.0.sh`/`deploy-boot-7.0.sh`.
  Precisa ser montada manualmente dentro do PS4 para o teste.
- **Risco real, não testado em lugar nenhum do projeto:** o payload original
  (`ps4-linux-payloads/linux/ps4-kexec-common/linux_boot.c`,
  `cpu_quiesce_gate()`) faz um quiesce pesado de hardware (reset de GPU,
  MTRR, E820 customizado, reserva de VRAM) partindo do FreeBSD/Orbis limpo
  ANTES do primeiro boot do Linux. Um kexec nativo, chamado do Linux já
  rodando, pula esse trabalho inteiramente — não se sabe se o próximo kernel
  inicializa corretamente GPU/VRAM/MTRR/E820 nesse hardware customizado
  (`X86_SUBARCH_PS4`).
- **Mitigação:** pior caso realista é travamento silencioso exigindo power
  cycle físico — que já é o status quo quando o disco falha com R/W. Kexec é
  operação 100% RAM/CPU, sem risco a NVRAM/firmware/storage.
- **Nenhum `bootargs.txt` hoje tem UART funcional no kernel v5.**
  `bootargs-7.0-s5-poweroff-fix-20260725-v5.txt` usa só `console=tty0`, sem
  `earlycon`/uart8250 — não produziria log algum se travar. Precisa de uma
  variante corrigida antes de qualquer teste (ver Etapa 0).

## Status (atualizado 2026-07-27 17:30)

- **Etapa 0 (bootargs UART):** ✅ concluída — `bootargs-7.0-s5-poweroff-fix-20260725-v5-uart.txt`
  já estava staged em `/mnt/boot` e usa o caminho MMIO correto (`earlycon=uart8250,mmio32,0xC890E000`).
- **Etapa 1 (kexec-tools):** ✅ concluída — `kexec-tools 2.0.32` já instalado no rootfs em uso,
  `kexec_load_disabled=0`.
- **Etapa 2 (montar BOOT + captura UART):** ✅ concluída — `/dev/sdb1` monta manualmente em
  `/mnt/boot` dentro do Linux rodando.
- **Etapa 3 (kexec do MESMO kernel, risco mínimo):** ✅ testada (`test-06-etapa3-mesmo-kernel`,
  17:41). `kexec -l`+`kexec -e` do kernel idêntico ao rodando → boot novo confirmado via UART,
  silêncio após `printk: legacy bootconsole [uart8250] disabled` (`0.714433s`).
- **Etapa 4 (kexec do kernel-alvo v5):** ✅ testada (`test-05-v5`, 17:19). Boot novo confirmado
  (`#8` vs `#2` rodando, cmdline correto), mesmo silêncio após `0.715481s`.
- **⚠️ CORREÇÃO (17:55): a conclusão de "kexec trava em 0.7s" tirada às 17:44 estava ERRADA.**
  Reexame dos logs `test-01`/`test-03` (boots normais via disco, SEM kexec, sucesso confirmado)
  mostrou que a UART também fica muda no mesmo ponto em boots que funcionam — não é evidência de
  travamento, é o driver 8250 "real" nunca assumindo a saída após o `earlycon`.
- **✅ TESTE DEFINITIVO (`test-07-keep-bootcon`, 18:46-18:56):** repetida a Etapa 3 com
  `keep_bootcon` no bootargs (evita silenciar a UART) + 6 minutos completos de espera por ping.
  Resultado: o boot avança de verdade bem mais longe (SATA storm do HD interno em ~40-53s, driver
  `mts`/eth0 registrado com sucesso em `119.665s`), mas **trava de fato logo depois disso** —
  mais de 5 minutos sem nenhum log adicional nem ping. **Esta é a conclusão real e confirmada:
  kexec nativo trava, mas em ~120s de kernel time (após Ethernet, provavelmente ao tentar montar
  o rootfs via USB), não em 0.7s.**
- **Hipótese atual:** falta o `disableMSI` do controlador USB 3.0 xHCI que `cpu_quiesce_gate()`
  faz só na transição original Orbis→Linux — sem ele, o xHCI pode ficar num estado de IRQ/MSI
  inconsistente que trava o driver do kernel novo ao tentar montar o HD USB (rootfs).
- **Etapa 5 (oficialização):** bloqueada — kexec nativo puro não é viável até essa causa (ou
  outra) ser resolvida. Ver
  `memory/kexec-nativo-mecanismo-funciona-mas-v5-trava-pos-console-handoff-2026-07-27.md` para o
  histórico completo e próximos passos (investigar reset de xHCI antes do `kexec -e`).
- **Tentativa `test-08-xhci-unbind` (20:40): FALHOU por motivo metodológico, não conclusiva.**
  `unbind` do driver `xhci_aeolia` ao vivo quebrou o próprio `sshd`/sessão (root está em
  `/dev/sdb2`, no mesmo controlador) antes de confirmar se o `kexec -e` chegou a rodar. Exigiu
  power cycle físico. Próxima tentativa precisa rodar via `/dev/shm` (tmpfs) ou `setpci` direto
  na config space, sem depender de I/O de disco novo após o `unbind`.

## Etapas (incrementais, cada uma reversível e testável isoladamente)

### Etapa 0 — Bootargs de teste com UART corrigido (pré-requisito)

Sem isso, um travamento do warm-reboot é invisível.

1. Criar `boot_referencia/bootargs-7.0-s5-poweroff-fix-20260725-v5-uart.txt`
   (arquivo NOVO, não editar o v5 original) — mesma base do v5, trocando
   `console=tty0` por:
   `earlycon=uart8250,mmio32,0xC890E000 console=uart8250,mmio32,0xC890E000 console=tty0`
2. Validar esse bootargs isoladamente primeiro, via boot normal por disco
   (`deploy-boot-7.0.sh s5-poweroff-fix-20260725-v5-uart`, reaproveitando
   bzImage/initramfs da v5 via `cp` explícito) + captura UART — isola "UART
   funciona no v5" de "kexec funciona", antes de empilhar as duas variáveis.

### Etapa 1 — Instalar/validar `kexec-tools` via SSH (sem rebuild de imagem)

Veredito rápido antes de comprometer o pkglist e rebuildar o rootfs inteiro.

```bash
sshpass -p ps4 ssh root@192.168.6.128 "pacman -Sy --noconfirm kexec-tools"
sshpass -p ps4 ssh root@192.168.6.128 "kexec --version; cat /sys/kernel/kexec_loaded /proc/sys/kernel/kexec_load_disabled 2>&1"
```

Se `pacman -Sy` falhar por falta de rede dentro do PS4: compilar
`kexec-tools` estaticamente no host e copiar via `scp` para
`/usr/local/sbin/kexec`.

**Critério de avanço:** `kexec --version` responde e
`kexec_load_disabled` = `0`.

### Etapa 2 — Montar BOOT + preparar captura UART (antes de qualquer kexec)

```bash
sshpass -p ps4 ssh root@192.168.6.128 "mkdir -p /mnt/boot && mount /dev/sdb1 /mnt/boot && ls -la /mnt/boot"
scripts/uart_stop.sh   # garantir que não há captura órfã
scripts/uart_start.sh 900 kexec-warm-reboot-test-01
tail -f tests/uart_logs/kexec-warm-reboot-test-01_*.log
```

Avisar o usuário e esperar confirmação ("pronto") antes de qualquer
`kexec -e` — é o ponto de não-retorno de cada teste.

### Etapa 3 — Teste de risco mínimo: kexec do MESMO kernel já rodando

Isola "o mecanismo kexec funciona nesse hardware" de "o kernel v5 funciona".

```bash
# 1. Carregar (reversível — kexec -u desfaz):
sshpass -p ps4 ssh root@192.168.6.128 \
  "kexec -l /mnt/boot/bzImage --initrd=/mnt/boot/initramfs.cpio.gz --append=\"$(cat /proc/cmdline)\""

# 2. Confirmar /sys/kernel/kexec_loaded == 1, SÓ ENTÃO (após confirmação do usuário):
sshpass -p ps4 ssh root@192.168.6.128 "sync; kexec -e"
```

Observar UART (nova sequência de boot) e SSH voltando (respeitar
`rootdelay=10` + tempo de systemd/sshd).

**Por que é o teste de menor risco:** GPU/VRAM/MTRR/E820 já estão
corretamente inicializados para ESSE bzImage na sessão atual. Se mesmo esse
kexec trivial travar, a conclusão já é "kexec nativo não é viável sem
replicar o quiesce", sem queimar uma tentativa no kernel v5 (que é o alvo de
debug real).

### Etapa 4 — Kernel-alvo v5 + procedimento de travamento

Só após Etapa 3 ter sucesso pelo menos duas vezes (descartar sorte).

1. Copiar `bzImage-7.0-s5-poweroff-fix-20260725-v5`,
   `initramfs-7.0-s5-poweroff-fix-20260725-v5.cpio.gz` e o bootargs corrigido
   da Etapa 0 para `/mnt/boot/*-v5` (nomes distintos dos genéricos, sem
   sobrescrever o que está ativo — mantém reversibilidade).
2. Avisar/confirmar antes do `kexec -e`.
3. Observar UART.

**Se travar sem log nenhum:** power cycle físico (não é regressão — já é o
status quo com falha de disco). Registrar o incidente em
`consolidado/LICOES_APRENDIDAS.md` e/ou `ps4_hardware_memory.db`
(`test_history`). Se travar consistentemente sem earlycon nenhum, a causa
provável é a ausência do quiesce de `cpu_quiesce_gate()` — investigação de
extrair essas rotinas de HW fica fora do escopo deste plano.

### Etapa 5 — Oficialização (se Etapas 3-4 forem confiáveis)

Após repetibilidade demonstrada (recomendação: 3 execuções consecutivas sem
travar, incluindo pelo menos uma ida-e-volta entre kernels):

1. Adicionar `kexec-tools` a `pkglist.x86_64.txt` e rodar
   `01-build-image-7.0.sh` para oficializar no rootfs.
2. Criar `scripts/kexec_reboot.sh <TAG>` (estilo `deploy-boot-7.0.sh`:
   `set -euo pipefail`, checagens de sanidade, sem fallback silencioso):
   recebe `<TAG>`, faz `scp` dos 3 artefatos para `/root/kexec-stage/` no PS4
   (sem tocar em `/mnt/boot`), valida com `kexec -l && kexec -u` (dry-run),
   só executa `kexec -e` após confirmação explícita, loga a tentativa em
   `test_history`.
3. Documentar no `AGENTS.md` como ATALHO de iteração — deixar claro que o
   fluxo `00-build-kernel → 01-build-image → deploy-boot` continua sendo o
   caminho para "oficializar" uma tag como boot padrão do HD (o que
   sobrevive a power cycle a frio; kexec nativo não substitui isso).
4. Manter sempre `deploy-boot-7.0.sh` com a última tag "conhecida boa" no HD
   físico, para que um power cycle após `kexec -e` malsucedido volte a um
   kernel funcional pelo caminho normal.

## Resumo das etapas

| Etapa | O que valida | Reversível? | Bloqueante para próxima? |
|---|---|---|---|
| 0 | bootargs UART corrigido, testado via boot normal por disco | sim | sim |
| 1 | `kexec-tools` instala e roda nesse userspace/kernel | sim | sim |
| 2 | BOOT montável + UART capturando ANTES do 1º kexec | sim | sim |
| 3 | kexec do MESMO kernel já rodando (isola o mecanismo) | load sim / exec não | sim |
| 4 | kexec do kernel-alvo v5 (isola o quiesce/HW) | load sim / exec não | sim, p/ Etapa 5 |
| 5 | Script reutilizável + oficialização no pkglist | sim | — |

## Arquivos críticos

- `distros/arch_minimal_v2/pkglist.x86_64.txt`
- `distros/arch_minimal_v2/deploy-boot-7.0.sh` (referência de estilo)
- `distros/arch_minimal_v2/boot_referencia/bootargs-7.0-s5-poweroff-fix-20260725-v5.txt`
- `scripts/uart_start.sh` / `scripts/uart_stop.sh`
- `ps4-linux-payloads/linux/ps4-kexec-common/linux_boot.c` (referência do que o payload original faz e que o kexec nativo NÃO replica)
- `AGENTS.md`, `consolidado/LICOES_APRENDIDAS.md`

## Verificação end-to-end

1. Etapa 0 valida sozinha: boot via disco com bootargs novo produz log UART completo até login (comparar com `memory/console-ttys0-bootargs-causa-tela-preta-2026-07-27.md` para confirmar que não é o bug antigo).
2. Etapa 3 valida sozinha: `kexec -e` do mesmo kernel retorna ao login (SSH responde, UART mostra novo boot) — critério objetivo de sucesso do mecanismo.
3. Etapa 4 valida sozinha: mesmo critério, mas com o kernel v5 — sucesso aqui já desbloqueia o debug do S5 em si (fora do escopo deste plano, mas é o objetivo final que motivou tudo isso).
4. Etapa 5 valida com 3 repetições consecutivas antes de considerar "pronto para uso rotineiro".