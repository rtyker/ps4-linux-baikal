---
name: kexec-nativo-mecanismo-funciona-mas-v5-trava-pos-console-handoff
description: CORRIGIDO — "trava pós-console-handoff" era diagnóstico ERRADO. UART fica muda em TODO boot (kexec ou não) porque o console real uart8250 nunca assume após o earlycon. Conclusão de "kexec trava" não está confirmada; teste real precisa de `keep_bootcon` + espera mais longa por ping/SSH.
metadata:
  type: project
---

# kexec nativo: CORREÇÃO — silêncio da UART não prova travamento (2026-07-27)

## ⚠️ Este arquivo contém uma correção de um erro de diagnóstico do próprio autor

A primeira versão desta memória concluía que o `kexec -e` nativo travava o sistema
logo após `printk: legacy bootconsole [uart8250] disabled` (~0.71s de kernel time),
tanto para o kernel-alvo v5 quanto para o mesmo kernel já rodando. **Essa conclusão foi
tirada cedo demais e provavelmente está errada.**

## O que invalidou a conclusão original

Reexaminando os logs `tests/uart_logs/kexec-warm-reboot-test-01_20260727_160556.bin` e
`test-03_20260727_162814.bin` — que são **boots normais via disco/payload Orbis, SEM
NENHUM kexec envolvido**, e que sabidamente terminaram em boot bem-sucedido (SSH
funcionou logo depois, confirmado na sessão do mesmo dia) — **ambos também têm
`printk: legacy bootconsole [uart8250] disabled` como ÚLTIMA linha capturada**, em
timestamps de kernel diferentes (`0.718535s` no test-01, `3.234355s` no test-03).

Ou seja: **a UART fica muda depois dessa mensagem em TODO boot deste sistema — kexec ou
não —, mesmo em boots que sabidamente completam com sucesso.** Não é sintoma de
travamento. É comportamento esperado do Linux: o `earlycon=` (bootconsole) é desligado
quando o console "real" (`console=uart8250,mmio32,...`) deveria assumir — mas nesse
hardware customizado (Baikal, UART em MMIO não-padrão `0xC890E000`), o driver 8250
"de verdade" muito provavelmente nunca se registra como console persistente (porta não
descrita nas tabelas ACPI SPCR/DBG2 que esse driver normalmente precisa para bindar),
então a saída simplesmente para — enquanto o boot continua por baixo, silenciosamente,
possivelmente até o login.

## Consequência para os testes `test-05-v5` e `test-06-etapa3-mesmo-kernel`

Não dá mais para afirmar que o `kexec -e` nativo travou o sistema. O que sabemos de
fato:
- `kexec -l`+`kexec -e` executam e trocam de kernel em RAM de verdade (boot novo
  confirmado via UART, com `Linux version`/`Kernel command line` corretos).
- A UART fica muda no mesmo ponto de sempre — **isso não é evidência de travamento**.
- **A evidência real usada para concluir "travou" foi só a ausência de ping/SSH.** Mas
  o tempo de espera foi curto demais para ser conclusivo: ~5 min no `test-05-v5` (razoável,
  mas não confirmado com log intermediário), e só **~45 segundos** no
  `test-06-etapa3-mesmo-kernel` — tempo insuficiente para um boot completo com
  `rootdelay=10` + `systemd` + inicialização de rede neste hardware, que historicamente
  leva bem mais que isso.
- Portanto: **ainda não sabemos se o kexec nativo realmente trava, ou se ele completa o
  boot só que sem log algum na UART depois de ~0.7-3s.**

## Correção necessária antes do próximo teste

Adicionar `keep_bootcon` ao bootargs de teste. Essa opção do kernel Linux impede que o
`earlycon`/bootconsole seja desativado quando o console "real" assume — mantém a saída
serial pelo boot inteiro, dando sinal real de progresso (ou de travamento de verdade,
se houver) em vez de silêncio ambíguo.

Também esperar bem mais tempo por ping/SSH antes de declarar "travou" (pelo menos 3-5
minutos com tentativas de ping a cada 10-15s), e preferir observar até aparecer
literalmente MAIS log (ou a ausência dele por vários minutos reais) em vez de decidir
rápido.

## Contexto original (para referência) — RE-VERIFICAR, não confiar cegamente

Sessão de teste ao vivo do `PLANO_KEXEC_WARM_REBOOT_2026-07-27.md`, Etapas 3 e 4.
Ambos os testes (`test-05-v5` 17:19, `test-06-etapa3-mesmo-kernel` 17:41) mostraram
boot novo real via UART (build/cmdline corretos) até a mensagem de bootconsole
disabled, e depois silêncio. Usuário fez power cycle físico em ambos os casos — mas
isso pode ter sido prematuro (interrompendo um boot que talvez completasse), não
necessariamente confirma travamento real.

`cpu_quiesce_gate()` em `ps4-linux-payloads/linux/ps4-kexec-common/linux_boot.c`
(payload Orbis original) faz, antes do PRIMEIRO boot do Linux: reset de interrupt/APIC
por CPU, setup de MTRR, halt de CPUs secundárias, nova hierarquia de page tables,
GDT customizado, `fix_acpi_tables()` (chamado ANTES do quiesce, em
`hook_icc_query_nowait`), disable de IOMMU/MSI (específico Baikal), reconfiguração de
VRAM e softreset do bloco GPU (CP/MEC/SDMA/RLC via MMIO `0xe480xxxx`), setup de pinos de
áudio HDMI. Nada disso é replicado por um `kexec -e` nativo chamado de dentro do Linux
já rodando. **Isso continua sendo uma hipótese válida para uma eventual falha real**,
mas não foi confirmada nem descartada ainda — precisa do teste com `keep_bootcon` para
saber se há falha real ou não.

## Teste com `keep_bootcon` (`test-07-keep-bootcon`, 18:46-18:56) — RESULTADO FINAL

Criado `bootargs-7.0-20260727-current-uart-keep-bootcon.txt` (clone do `bootargs.txt`
genérico do kernel `#2` já rodando + `keep_bootcon`), copiado para `/mnt/boot` no PS4.
Repetida a Etapa 3 (kexec do mesmo kernel `#2`). Desta vez a UART **não** ficou muda
cedo — continuou logando o boot inteiro. Monitorado com paciência: **6 minutos
completos** de espera (24 checagens de ping a cada 15s), sem concluir nada até o fim do
ciclo.

**O boot avançou MUITO além do ponto anterior** (que era só a UART calando, não uma
trava real):
- `[36.6s-53.5s]`: tempestade de resets SATA do HD interno (`ata1`) — comportamento
  **já documentado e conhecido** deste hardware (não é causado pelo kexec).
- `[87s-119.6s]`: driver `mts` (Ethernet GBE) inicializa normalmente — calibração PHY,
  polling MDIO (resultado de sempre: PHY não responde dado real, problema à parte já
  documentado em `mac-en2-descartado-phy-nunca-acorda-2026-07-23.md` e correlatos —
  não é novidade nem culpa do kexec).
- `[119.665s]`: **`mts 0000:00:14.1: mts registrado como eth0, MAC 2c:cc:44:3f:69:5f`**
  — última linha capturada.
- **Depois disso: silêncio total por mais de 5 minutos, log parado em 68048 bytes, sem
  UART, sem ping, sem SSH.** Desta vez a evidência é sólida (`keep_bootcon` garante que
  a UART continuaria logando se o kernel continuasse rodando, e 6 minutos é tempo mais
  que suficiente pra esse hardware chegar em rede/SSH — boots normais chegam em bem
  menos tempo que isso).

## CONCLUSÃO FINAL (confirmada, alta confiança)

**O `kexec` nativo do Linux trava de verdade neste hardware — mas bem mais tarde do que
o diagnóstico inicial (errado) apontava.** Não é no handoff do console (~0.7s, isso era
só a UART calando, comportamento normal); é **logo depois da inicialização do driver
Ethernet `mts` (~120s de kernel time)**, no ponto em que o boot normalmente seguiria
para montar o rootfs (USB `sdb`) e chegar no `switch_root`/systemd.

**Hipótese mais forte agora:** o subsistema USB (controlador xHCI, `0000:00:14.7` no
Baikal) é o próximo grande subsistema de hardware a ser tocado depois do Ethernet nessa
sequência de boot (é dele que depende montar `/dev/sdb` = rootfs). `cpu_quiesce_gate()`
explicitamente desabilita MSI do xHCI (`disableMSI(0xf80a70e0)`) antes do primeiro boot
do Linux — um `kexec` nativo nunca faz isso. Se o controlador xHCI ficar num estado de
IRQ/MSI inconsistente (deixado pelo kernel anterior, sem o reset que só a transição
Orbis→Linux original faz), o driver xHCI do kernel novo pode travar tentando
inicializar/enumerar o HD USB — silenciosamente, sem panic, exatamente como observado.
Isso é consistente com a hipótese original sobre falta de quiesce de hardware, só que
apontando para USB/xHCI em vez de GPU como o subsistema culpado (GPU nem chega a ser
tocado nesse ponto do boot — `drm`/`amdgpu` normalmente inicializa mais tarde, depois
do rootfs montado, baseado nos boots completos de referência do projeto).

## Tentativa de mitigação: unbind do xHCI antes do kexec (`test-08-xhci-unbind`, 20:40) — FALHOU POR MOTIVO METODOLÓGICO

Investigado `drivers/usb/host/xhci-aeolia.c` na árvore do kernel
(`/mnt/hdauxiliar/temp/kernel_build_7.0`): o driver `xhci_aeolia` (custom, não é o
`xhci-pci` genérico — o dispositivo Baikal se anuncia como classe PCI `0880`, não
`0c0330`) **tem** um hook `.shutdown` (`xhci_hcd_pci_shutdown`), chamado automaticamente
pelo Linux em qualquer `kexec`/reboot via `device_shutdown()`. Mas esse hook só para o
controlador (`hcd->driver->shutdown(hcd)`) — **não** chama `pci_disable_device()`, que é
o que de fato limpa o bit de MSI-enable na config space PCI (isso só acontece no
`.remove()` completo). Ou seja, existe um gap real entre o que o `kexec` nativo faz
automaticamente e o `disableMSI()` explícito que o payload Orbis original faz.

Testado: `kexec -l` (mesmo kernel `#2`) → `sync` → `echo 0000:00:14.7 >
/sys/bus/pci/drivers/xhci_aeolia/unbind` (força `.remove()` completo) → `kexec -e`, tudo
num único comando SSH.

**Resultado: o teste se autossabotou antes de chegar no `kexec -e`.** `/` está montado em
`/dev/sdb2`, que depende do mesmo controlador xHCI sendo desligado. Assim que o `unbind`
rodou, o próprio `sshd` (que precisa ler binários/PAM/libs do disco a cada nova conexão)
passou a falhar — `Connection reset by peer` durante o handshake SSH, TCP na porta 22
continua aceitando conexão mas cai logo depois. Ping continuou respondendo (kernel e rede
seguem vivos), mas não há mais como confirmar via SSH se o `kexec -e` chegou a executar
dentro do mesmo comando encadeado (`;`) — o mais provável é que a própria sessão bash
remota morreu no meio do encadeamento, antes de chegar em `kexec -e`. Sistema ficou numa
zona inutilizável (kernel rodando, rede OK, rootfs quebrado) — exigiu power cycle físico.

**Lição:** testar `unbind` do controlador que hospeda o `/` ativo não pode ser feito de
dentro de uma sessão cujos próprios processos (sshd, bash, coreutils sob demanda) dependem
desse mesmo disco. Precisa de uma abordagem que não depender de I/O de disco novo depois
do `unbind` — ex: um binário estaticamente linkado, pré-carregado inteiramente em
cache/tmpfs antes do `sync`, executando `unbind` e `kexec -e` sem tocar disco de novo
nesse meio-tempo (ou copiar previamente um script para `tmpfs`/`/dev/shm` e rodá-lo a
partir de lá, já que `/dev/shm` não depende do xHCI).

## Tentativa de mitigação nº2: `setpci` só no bit MSI-enable, SEM unbind (`test-09-setpci-msi`, 2026-07-28) — TAMBÉM FALHOU, e de forma reveladora

Objetivo: opção "c" da lista anterior — testar se só zerar o bit MSI-enable (offset
`CAP_MSI+2.w`, bit 0) na config space do xHCI (`0000:00:14.7`), sem fazer `unbind`
completo do driver, seria seguro o bastante (mexe só na config space PCI, não desmonta o
dispositivo).

Executado via SSH normal (WiFi, `192.168.6.128`, kernel ainda **não** kexeceado, boot
original de disco): `setpci -s 0000:00:14.7 CAP_MSI+2.w` leu `0187` (MSI Enable=1);
escrito `0186` (bit 0 zerado) com sucesso confirmado pela releitura.

**Resultado: mesmo sintoma exato do `test-08-xhci-unbind`.** Nos comandos seguintes
(inclusive uma tentativa de LER o valor de volta, e 3 tentativas de reverter o bit para
`0187`), o SSH parou de completar o handshake — primeiro `Connection timed out during
banner exchange`, depois consistentemente `kex_exchange_identification: read: Connection
reset by peer` (porta 22 TCP ainda aceita SYN, mas cai antes do banner SSH). **Ping
continuou 100% estável o tempo todo** (kernel e rede vivos). 3 tentativas de reverter o
bit com pausas de ~4s entre elas, todas falharam da mesma forma. Não foi possível
confirmar nem reverter o estado — PS4 ficou preso em zona inutilizável de novo (rede OK,
mas SSH/disco quebrado), exigindo novo power cycle físico.

**Isso é uma descoberta importante, não só uma repetição da falha:** o `test-08` tinha
uma explicação "óbvia" (fazer `unbind` de um driver enquanto o próprio `/` depende dele).
Mas este teste **não fez unbind nenhum** — só escreveu 1 bit na config space PCI, com o
driver `xhci_aeolia` continuando "bind" e pensando que está tudo normal. O simples fato
de desligar o MSI Enable ao vivo, sem o driver saber, já é suficiente para quebrar o I/O
do HD USB imediatamente (o driver continua esperando IRQs via MSI para completar
transferências DMA, que nunca mais chegam — clássico "IRQ perdida" após reconfiguração de
MSI sem coordenação com o driver). **Isso refuta a ideia de que `setpci` sem unbind seria
uma alternativa mais segura** — na prática, qualquer manipulação ao vivo do estado
MSI/xHCI deste controlador quebra o disco imediatamente, com ou sem unbind formal.

**Confirmação visual (foto da tela HDMI/tty1, `/tmp/001.jpeg`, fornecida pelo usuário
depois do teste):** o mecanismo exato do travamento agora está documentado com precisão
— não é um hang silencioso de I/O, é um **erro real de journal EXT4** detectado pelo
próprio kernel:
```
[516.816715] EXT4-fs error (device sdb2) in ext4_setattr:6028: Journal has aborted
[516.816714] EXT4-fs error (device sdb2): ext4_journal_check_start:86: comm systemd-udevd: Detected aborted journal
[516.816917] EXT4-fs error (device sdb2): ext4_journal_check_start:86: comm systemd: Detected aborted journal
[516.817294] EXT4-fs (sdb2): Remounting filesystem read-only
[516.817296] EXT4-fs (sdb2): Remounting filesystem read-only
[516.830051] EXT4-fs (sdb2): shut down requested (2)
```
Ou seja: o `setpci` no bit MSI-enable causou uma falha de I/O real e detectada (não só
"sem resposta") no disco por trás do xHCI, o journal do EXT4 abortou, tanto
`systemd-udevd` quanto o `systemd` PID 1 detectaram o journal abortado nas suas próprias
operações de I/O, o filesystem raiz remontou read-only duas vezes seguidas e por fim o
EXT4 forçou um "shut down" do próprio filesystem (`shut down requested (2)`). Isso
explica com precisão por que o `sshd` parou de completar handshakes: o `/` ficou
inutilizável (read-only e depois desligado), então qualquer processo/lib que precisasse
gravar (logs, PAM, sessão) falhava, mesmo o kernel e a rede continuando vivos.

**Consequência para a hipótese original:** isso na verdade FORTALECE a hipótese de que
`disableMSI()` do xHCI é algo que só pode ser feito com segurança ANTES do driver
`xhci_aeolia` sequer atacar o dispositivo (como faz o `cpu_quiesce_gate()` do payload
Orbis original, que roda antes de qualquer driver Linux existir) — nunca ao vivo, com o
driver já rodando e dependendo do controlador.

## Teste de diagnóstico: `pci=nomsi` no kernel-alvo (`test-10-pci-nomsi`, 2026-07-28) — RESULTADO: HIPÓTESE REFUTADA NA FORMA SIMPLES, NOVO DADO IMPORTANTE

Testado o único passo de baixo risco que restava: bootargs do **kernel-alvo do kexec**
(não manipulação ao vivo) com `keep_bootcon pci=nomsi` adicionados, via
`kexec -l /mnt/boot/bzImage --initrd=/mnt/boot/initramfs.cpio.gz --command-line="..."`
seguido de `kexec -e` (confirmado pelo usuário antes de disparar). Cmdline confirmado
aplicado no boot (`...otcon pci=nomsi ...` visível no início do log UART).

**Resultado: o boot foi BEM MAIS LONGE do que antes até certo ponto (chegou em
`Run /init as init process` aos 3.78s, bem cedo), mas travou ainda mais cedo que o
`kexec` normal** — parou definitivamente em **13.78s de kernel time**, logo após três
mensagens seguidas:
```
[   13.784164] sdhci-pci 0000:00:14.3: SDHCI controller found [104d:90da] (rev 0)
[   13.784130] pci 0000:00:01.0: deferred probe pending: (reason unknown)
[   13.784130] pci 0000:00:14.2: deferred probe pending: (reason unknown)
[   13.784130] pci 0000:00:14.7: deferred probe pending: (reason unknown)
```
Note que `0000:00:14.7` é exatamente o xHCI investigado. Depois disso: **5 minutos
completos de silêncio total** (log parado em 33818 bytes, ping 100% falho o tempo
inteiro) — mesmo nível de confiança do `test-07` (que usou 6 min), então não é ambiguidade
de UART calada, é travamento real confirmado.

**Interpretação:** `pci=nomsi` NÃO resolveu o problema — na verdade piorou, travando MUITO
mais cedo (13.8s vs ~120s do kexec normal sem `nomsi`). Isso é evidência forte de que este
hardware customizado (Baikal PCIe Root Complex) **provavelmente não tem as linhas legadas
INTx (INTA/B/C/D) roteadas/fiadas** — comum em SoCs customizados que só suportam MSI/MSI-X
— então desabilitar MSI totalmente impede vários dispositivos de conseguir uma IRQ
funcional, causando o loop de "deferred probe" travar ali mesmo, bem antes de chegar no
Ethernet ou no USB. **A hipótese simples "só faltava desabilitar MSI" está refutada.** O
problema real do `kexec` nativo (trava ~120s, pós-Ethernet/pré-USB) continua sem
explicação causal confirmada — só sabemos que não é "MSI presente demais"; pode ser
"estado de MSI inconsistente/deixado pelo kernel anterior" (não "MSI ausente"), que é uma
hipótese mais sutil e mais difícil de testar sem manipulação ao vivo (já descartada por
quebrar o disco).

## Teste de diagnóstico: `initcall_debug` no kernel-alvo (`test-11-initcall-debug`, 2026-07-28) — LOCALIZAÇÃO MAIS PRECISA DO TRAVAMENTO

Testado bootargs do kernel-alvo do `kexec` (sem `pci=nomsi`, já refutado) com
`keep_bootcon initcall_debug`. Monitorado 6 minutos completos (24 checagens de
ping+tamanho de log a cada 15s), mesmo protocolo do `test-07`.

**O boot avançou mais longe e com muito mais detalhe que antes.** Com `initcall_debug`
visível, o log capturou toda a sequência de calibração de PHY do `mts.ko` (mesma já
documentada em `mac-en2-descartado-phy-nunca-acorda-2026-07-23.md` — PHY nunca retorna
dado real via MDIO Clause 22/45, `IMR=0x0`), **incluindo uma linha nova não vista antes
em nenhum log anterior:**
```
[   95.207792] mts 0000:00:14.1: ICC cmd 4 0x38 (GBE power-on): ret=20 reply=01 tries=1
[   95.227728] mts 0000:00:14.1: ICC cmd 4 0x38: GBE power-on CONFIRMADO (reply=0x01)
```
(o driver já envia um comando ICC `major=4,minor=0x38` rotulado "GBE power-on" e recebe
confirmação — **não confundir com o `major=5,minor=0x41` já descartado** em
`baikal-gbe-e-sky2-nao-stmmac.md`; são serviços ICC diferentes. Não investigado a fundo
nesta sessão, mas registrado para referência futura do bug de RX.)

**Ponto exato do travamento, agora identificado com precisão inédita:**
```
[  127.706128] mts 0000:00:14.1: mts registrado como eth0, MAC 2c:cc:44:3f:69:5f
[  127.709787] probe of 0000:00:14.1 returned 0 after 32794049 usecs
[  127.717796] initcall mts_driver_init+0x0/0x1000 [mts] returned 0 after 32802050 usecs
```
Depois disso: **6 minutos completos de silêncio total** (log parado em 173370 bytes,
232s+ de estagnação confirmada, ping 100% falho o tempo todo) — mesmo nível de confiança
do `test-07`.

**Achado crucial:** essa é a ÚLTIMA linha `calling X+0x0/...` de todo o log — não
`initcall mts_driver_init ... returned 0`, mas a busca por qualquer linha `calling`
posterior (`grep "calling "`) não encontra NADA depois dela. Ou seja: **o próximo
initcall/módulo nunca sequer COMEÇA a ser chamado.** Note também que `mts_driver_init`
roda com `@ 294` (PID de um worker do `systemd-udevd`, não `@ 1`/kernel init) — confirma
que `mts.ko` é carregado dinamicamente via coldplug do udev (por regra de módulo por
PCI ID), não é built-in.

**Interpretação:** o travamento não está dentro de um driver/initcall síncrono
instrumentado — está em algo que roda FORA do caminho `do_one_initcall()`, quase certamente
no processamento de uevents do `systemd-udevd` tentando processar o PRÓXIMO dispositivo
(muito provavelmente o xHCI `0000:00:14.7`, coerente com o `test-10`, que mostrou
exatamente esse dispositivo — junto com `0000:00:14.2` e `0000:00:01.0` — preso em
`deferred probe pending` sob `pci=nomsi`). Isso é consistente com (mas não prova
definitivamente) a hipótese original de MSI/xHCI: mesmo sem `nomsi`, o próximo dispositivo
na fila de coldplug trava o worker do udev inteiro antes de conseguir processar qualquer
coisa depois do `mts`.

## Próximo passo (revisado 2026-07-28, pós test-09, test-10 e test-11)

**As 3 opções de baixo risco originalmente mapeadas foram esgotadas, e uma 4ª
(`initcall_debug`) já rendeu a localização mais precisa até agora:**
1. ~~`setpci` isolado sem unbind~~ — quebrou o disco (`test-09`).
2. ~~`unbind` completo~~ — quebrou o disco (`test-08`).
3. ~~`pci=nomsi` no kernel-alvo~~ — travou ainda mais cedo (`test-10`), mas revelou 3
   dispositivos em `deferred probe pending` (incl. xHCI).
4. ~~`initcall_debug` no kernel-alvo~~ — confirmou que o travamento em ~120-127s **não é
   um initcall síncrono**; é algo fora do caminho `do_one_initcall()`, quase certamente o
   worker do `systemd-udevd` travando ao processar o uevent do próximo dispositivo
   (`test-11`).

**Ideias para uma próxima sessão, nenhuma testada ainda:**
- Bootargs `udev.log_level=debug`/`systemd.log_level=debug` no kernel-alvo, para tentar
  capturar qual uevent específico o `systemd-udevd` está processando no momento do
  travamento (mais direto que inferir só pela ordem PCI).
- `pci=noaer` ou outros bootargs PCI mais seletivos (menos agressivos que `nomsi` total)
  no kernel-alvo, para tentar isolar sem quebrar o boot inteiro.
- Considerar que o objetivo original do plano (warm-reboot via kexec para acelerar testes
  de outro bug) pode estar bloqueado por um problema mais profundo/estrutural do PCIe
  Root Complex Baikal sob kexec, não só um detalhe de MSI — pode não valer mais a pena
  continuar essa via sem uma pista nova.

1. **Não repetir NENHUMA manipulação ao vivo de MSI/xHCI via SSH** — tanto `unbind`
   quanto `setpci` isolado já provaram quebrar o disco imediatamente, de forma
   irreversível dentro da mesma sessão (a tentativa de reverter o bit também falhou).
   Essa linha de investigação (mitigar ao vivo antes do `kexec -e`) está descartada.
2. **Único próximo passo que resta, de baixo risco:** testar bootargs com `pci=nomsi` no
   **kernel-alvo do kexec** (não no kernel atual — só afeta o próximo boot). Isso evita
   toda manipulação ao vivo: o kernel novo já sobe sem MSI desde o início, então não há
   "reconfiguração no meio do caminho" para o driver se confundir. Se isso permitir o
   `kexec` completar o boot até SSH, é evidência forte a favor da hipótese MSI/xHCI. Se
   ainda travar da mesma forma (~120s, pós-Ethernet), a hipótese cai e precisa de nova
   investigação (outro subsistema entre Ethernet e USB/rootfs).
3. Se `pci=nomsi` não resolver: o objetivo original do plano (reduzir bootcycles via
   kexec nativo) fica bloqueado por esse mecanismo; o ciclo continua sendo power-cycle
   físico + payload Orbis + boot Linux normal, sem atalho de warm-reboot, até surgir uma
   ideia nova.
