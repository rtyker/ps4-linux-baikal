---
name: build-deploy-20260730-sata-reverted-e-mecanismo-kexec-armed
description: Estado do build/deploy 20260730-sata-reverted (GBE MDIO fix isolado, SATA polling timer revertido) + esclarecimento do mecanismo real de handoff do kexec do payload PS4 Linux Payloads AIO
metadata:
  type: project
---

## Estado em 2026-07-30 (fim da sessão) — próximo boot ainda não confirmado

**Tag ativa no HD USB agora: `20260730-sata-reverted`.**

### O que essa tag contém
- Kernel = build `20260730-mdio-polarity-fix` (fix de polaridade MDIO Clause 22 em
  `drivers_mts/mts.c`, ver [[mdio-clause22-bug-polaridade-corrigido-2026-07-29]]) **menos** as
  mudanças de SATA da noite de 2026-07-29 (polling timer `hrtimer` de 1ms +
  instrumentação de debug em `ahci.c`/`ahci.h`/`libahci.c`/`xhci-aeolia.c`,
  ver `PLANO_SATA_POLLING_CORRECAO_2026-07-29.md`) — **essas mudanças foram
  revertidas via `git checkout --` na árvore `/mnt/hdauxiliar/temp/kernel_build_7.0`
  a pedido do usuário** ("tente DESFAZER as mudanças referente ao SATA do fim
  da noite"), porque eram só instrumentação/experimento nunca validado com
  sucesso e não fazem parte do escopo desta rodada (só GBE).
- `drivers/ata/libata-core.c` (quirk hardcoded `noncq` do `TOSHIBA MQ04ABF100`)
  **NÃO foi tocado** — é regra estabelecida antes, documentada em `AGENTS.md`,
  não faz parte do pacote "SATA do fim da noite".
- Build rodado com `taskset -c 0-3` (4 de 8 núcleos, a pedido do usuário para
  deixar recursos livres na máquina) — `real 19m47s`, sem erros, `bzImage`
  15.844.352 bytes (idêntico em tamanho ao build anterior).
- **rootfs NÃO foi tocado** — reaproveitado o rootfs completo já gravado
  (76.477 arquivos, validado estruturalmente íntegro) da rodada anterior
  (`20260730-mdio-polarity-fix`). Deploy feito via `deploy-boot-7.0.sh`
  (boot-only), não `02-burn-image-7.0.sh` — não havia necessidade de
  reparticionar/recriar o rootfs, só o kernel mudou.
- MD5 conferido origem→destino (`bzImage`, `bootargs.txt`, `initramfs.cpio.gz`),
  HD desmontado com segurança ao final.

### Mecanismo do kexec deste payload — ACHADO IMPORTANTE (esclarece ambiguidade anterior)

Analisando o log UART manual `uart_20260730_092637.log` (boot que o usuário
desligou antes de completar), ficou claro que o payload **"PS4 Linux Payloads
AIO" não faz o jump para o kernel Linux imediatamente após `sys_kexec()`**.
A sequência real é:

1. `sys_kexec(...)` carrega a imagem e imprime a cmdline completa.
2. `kexec successfully armed. Please shut down the system.` — o kexec fica
   **armado**, esperando o **reboot normal da Orbis** para efetivamente saltar.
3. A firmware stock roda o shutdown normal dela: cleanup de codecs de áudio
   (`Codec Opus ... was not properly unregistered`, ruído inofensivo),
   `[SceSysCore mini] call reboot(4000)`, espera processos do sistema pararem
   (`SceVnlru`, `SceBufdaemon0/1/2`), sync de buffers, `[PFS] umount(...)`.
4. **Só depois desse shutdown completo é que o salto real para o kernel Linux
   (earlycon/`Linux version`) deveria aparecer.**

Isso é **diferente** do incidente documentado anteriormente (sessão anterior:
log congelava no meio da própria impressão da cmdline, sem progresso nenhum —
esse sim era um hang real). No boot desta sessão (`uart_20260730_092637.log`),
o log mostra progresso normal por ~12s (09:27:24→09:27:36) através de várias
etapas de shutdown, e **termina abruptamente no meio de um `vn_printf`/lock
dump do unmount exFAT** — o usuário desligou manualmente o console ali,
achando que travou, mas os timestamps não mostram estagnação (cada
`Waiting (max 60 seconds)` retornou `done` quase instantaneamente).

**Implicação prática para o próximo boot:** não desligar o PS4 durante essa
janela de shutdown da Orbis pós-`kexec successfully armed` — ela pode levar
alguns segundos a mais de progresso normal antes do salto real acontecer.
Se travar de verdade, o sintoma esperado (por comparação com o incidente
anterior) é ausência total de novos bytes por 100+ segundos, não só uma
mensagem cortada.

### Pendente
- Confirmar em um próximo power-cycle se o boot chega ao earlycon/`Linux
  version` do kernel novo e sobe o `mts.ko`/`eth0` com o fix de MDIO ativo.
- Mitigação do SATA interno (`ata1`) via decoupling do `ahci_init_one()` no
  `xhci-aeolia.c` continua **deliberadamente adiada** (não incluída nesta tag).
