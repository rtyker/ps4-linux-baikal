---
name: s5-poweroff-fix-framing-corrigido-2026-07-30-testado-2026-07-31
description: S5 poweroff — fix de framing corrigido + sequência pre-sync+final, TESTADO AO VIVO 2026-07-31: OS desliga limpo mas S5 incompleto (luz azul acesa, fan ligado). Pré-sync major=4 minor=4 + final major=4 minor=1 (payload 20 bytes) NÃO corta energia total da fonte.
metadata:
  type: project
---

## Estado em 2026-07-30 (pausado a pedido do usuário, retomar depois)

**Plano aprovado:** `/home/anderson/.claude/plans/abstract-roaming-unicorn.md` (Resolver S5
incompleto no `poweroff -f`).

### Achado-chave desta sessão (novo, não documentado antes)

A tentativa de 2026-07-25 (tag `s5-poweroff-fix-20260725`, artefatos já descartados) reconstruiu
um "payload de 32 bytes" a partir de RE do dump Orbis 12.52, mas **o teste ao vivo não resolveu o
S5** (luz azul continuou acesa). Reabrindo a RE via `objdump` direto em
`consolidado/dumps_orbis/kmem_dump_1252.bin` (offsets `0x1d870e` e `0x1d8a3c`), achei uma provável
causa: **framing errado**.

- `_bpcie_icc_cmd()` (`ps4-bpcie-icc.c:173-213`) faz `sc->icc.request.length = ICC_HDR_SIZE +
  length` — o `length` que o driver Linux passa é **payload puro**, o header de 12 bytes é somado
  à parte.
- A RE confirma que o buffer TOTAL da Orbis (header + payload) é de 32 bytes (`length` no header
  Orbis = `0x0020`) — ou seja, o **payload real é de só 20 bytes**, não 32.
- O fix de 07-25 usava `uint8_t payload[32]` inteiro como "payload puro" → pacote real no fio de
  12+32=44 bytes, divergente do que a Orbis realmente envia. É plausível que o MCU tenha
  rejeitado/ignorado silenciosamente esse pacote de tamanho errado — explicando por que aquele
  teste não moveu o S5 nem um pouco.

Também confirmei por disassembly (offset `0x1d870e`, nunca antes verificado contra o binário real,
só citado num memory anterior) o comando de **pré-sync** (major=4, minor=4, flag=0x01 no payload)
que a Orbis dispara *antes* do comando final de shutdown (major=4, minor=1) — implementado agora
pela primeira vez no driver.

### Layout de payload corrigido (aplicado no código)

**Pré-sync (major=4, minor=4)** — `payload[20]`: `payload[0]=0x01` (flag), resto zero.

**Final (major=4, minor=1)** — `payload[20]`: `payload[0..1]=0x00,0x00` (flag, branch "ICC:
Shutdown." = poweroff normal), `payload[2]=cause`, `payload[3]=depth`, `payload[4]=hand`, resto
zero. Valores de cause/depth/hand mantidos como o melhor palpite já documentado (`0,1,0`) — a
origem exata (registradores `bl`/`r12b`/`r13b` computados a partir do argumento `howto` do
`kern_reboot` da Orbis) não foi rastreada até o fim nesta sessão; é a única incerteza
remanescente, não bloqueante para o primeiro teste.

### O que já foi feito
1. ✅ Código corrigido em `/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/ps4/ps4-bpcie-icc.c`
   (função `icc_shutdown()`) — sequência pré-sync (4/4) + final (4/1) com payloads de 20 bytes
   cada, logs `pr_info` antes/depois de cada comando, `mdelay(3000); WARN_ON(1);` mantido como
   salvaguarda de diagnóstico no final. **Ainda não commitado no git do kernel tree** (mudança
   está no working tree, junto com o resto do trabalho de GBE/SATA já ali).
2. ✅ Build feito: `sudo taskset -c 0-3 nice -n 10 ./00-build-kernel-7.0.sh
   20260730-s5-poweroff-fix` (50% CPU) — sem erros, `bzImage-7.0-20260730-s5-poweroff-fix`
   (15.844.352 bytes, mesmo tamanho de sempre) + `config-7.0-20260730-s5-poweroff-fix` gerados em
   `boot_referencia/`.
3. ✅ `bootargs-7.0-20260730-s5-poweroff-fix.txt` e `initramfs-7.0-20260730-s5-poweroff-fix.cpio.gz`
   copiados do baseline atual (`20260730-sata-polling-fase-ab`) — rootfs não muda, só o kernel.

### ✅ TESTE AO VIVO 2026-07-31 — RESULTADO
- **Deploy**: `sudo ./deploy-boot-7.0.sh 20260730-s5-poweroff-fix` (boot-only, rootfs intacto)
- **Teste**: SSH `sync && poweroff -f`
- **Resultado**: 
  - OS desligou limpo (rede 100% packet loss confirmado)
  - **MAS**: Luz azul **acesa**, fan **ligado**, monitor desligado
  - **Conclusão**: S5 incompleto — pré-sync ICC 4/4 + final ICC 4/1 (payload 20 bytes corrigido) **NÃO corta energia total da fonte (S5)**.
- **Registro**: `test_history` no SQLite `ps4_hardware_memory.db` + esta memória.

### Interpretação
O handshake ICC da Orbis para S5 é **mais rico** que apenas 2 comandos (vimos no boot capturado 2026-07-28: `icc 08-4001`, `icc:disabled thermal notification`, `eth0: link state changed to DOWN`, `ICC 05-00 polling`). O MCU/fonte provavelmente espera uma sequência completa ou comando dedicado não descoberto.

**S5 exige comando ICC dedicado ou toque manual no botão** — confirmado novamente.

### Rollback disponível
Tag `20260730-sata-polling-fase-ab` continua em `boot_referencia/` como baseline anterior — se o
teste do S5 causar qualquer regressão inesperada, `sudo ./deploy-boot-7.0.sh
20260730-sata-polling-fase-ab` volta ao estado confirmado (GBE + SATA funcionais).

## Estado em 2026-07-30 (pausado a pedido do usuário, retomar depois)

**Plano aprovado:** `/home/anderson/.claude/plans/abstract-roaming-unicorn.md` (Resolver S5
incompleto no `poweroff -f`).

### Achado-chave desta sessão (novo, não documentado antes)

A tentativa de 2026-07-25 (tag `s5-poweroff-fix-20260725`, artefatos já descartados) reconstruiu
um "payload de 32 bytes" a partir de RE do dump Orbis 12.52, mas **o teste ao vivo não resolveu o
S5** (luz azul continuou acesa). Reabrindo a RE via `objdump` direto em
`consolidado/dumps_orbis/kmem_dump_1252.bin` (offsets `0x1d870e` e `0x1d8a3c`), achei uma provável
causa: **framing errado**.

- `_bpcie_icc_cmd()` (`ps4-bpcie-icc.c:173-213`) faz `sc->icc.request.length = ICC_HDR_SIZE +
  length` — o `length` que o driver Linux passa é **payload puro**, o header de 12 bytes é somado
  à parte.
- A RE confirma que o buffer TOTAL da Orbis (header + payload) é de 32 bytes (`length` no header
  Orbis = `0x0020`) — ou seja, o **payload real é de só 20 bytes**, não 32.
- O fix de 07-25 usava `uint8_t payload[32]` inteiro como "payload puro" → pacote real no fio de
  12+32=44 bytes, divergente do que a Orbis realmente envia. É plausível que o MCU tenha
  rejeitado/ignorado silenciosamente esse pacote de tamanho errado — explicando por que aquele
  teste não moveu o S5 nem um pouco.

Também confirmei por disassembly (offset `0x1d870e`, nunca antes verificado contra o binário real,
só citado num memory anterior) o comando de **pré-sync** (major=4, minor=4, flag=0x01 no payload)
que a Orbis dispara *antes* do comando final de shutdown (major=4, minor=1) — implementado agora
pela primeira vez no driver.

### Layout de payload corrigido (aplicado no código)

**Pré-sync (major=4, minor=4)** — `payload[20]`: `payload[0]=0x01` (flag), resto zero.

**Final (major=4, minor=1)** — `payload[20]`: `payload[0..1]=0x00,0x00` (flag, branch "ICC:
Shutdown." = poweroff normal), `payload[2]=cause`, `payload[3]=depth`, `payload[4]=hand`, resto
zero. Valores de cause/depth/hand mantidos como o melhor palpite já documentado (`0,1,0`) — a
origem exata (registradores `bl`/`r12b`/`r13b` computados a partir do argumento `howto` do
`kern_reboot` da Orbis) não foi rastreada até o fim nesta sessão; é a única incerteza
remanescente, não bloqueante para o primeiro teste.

### O que já foi feito
1. ✅ Código corrigido em `/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/ps4/ps4-bpcie-icc.c`
   (função `icc_shutdown()`) — sequência pré-sync (4/4) + final (4/1) com payloads de 20 bytes
   cada, logs `pr_info` antes/depois de cada comando, `mdelay(3000); WARN_ON(1);` mantido como
   salvaguarda de diagnóstico no final. **Ainda não commitado no git do kernel tree** (mudança
   está no working tree, junto com o resto do trabalho de GBE/SATA já ali).
2. ✅ Build feito: `sudo taskset -c 0-3 nice -n 10 ./00-build-kernel-7.0.sh
   20260730-s5-poweroff-fix` (50% CPU) — sem erros, `bzImage-7.0-20260730-s5-poweroff-fix`
   (15.844.352 bytes, mesmo tamanho de sempre) + `config-7.0-20260730-s5-poweroff-fix` gerados em
   `boot_referencia/`.
3. ✅ `bootargs-7.0-20260730-s5-poweroff-fix.txt` e `initramfs-7.0-20260730-s5-poweroff-fix.cpio.gz`
   copiados do baseline atual (`20260730-sata-polling-fase-ab`) — rootfs não muda, só o kernel.

### Pendente (retomar daqui)
1. **HD USB do PS4 precisa estar conectado ao PC** para rodar `sudo ./deploy-boot-7.0.sh
   20260730-s5-poweroff-fix` (boot-only, mantém rootfs).
2. Antes do power-cycle físico: iniciar captura UART (`scripts/uart_start.sh <duração>
   s5-test`) — **netconsole não serve aqui**, a rede cai junto com o shutdown.
3. Usuário liga o PS4, aguarda boot completo, roda `sync && poweroff -f` via SSH.
4. Ler o log UART: procurar `icc: S5 pre-sync`, `icc: S5 shutdown final`, `ret=`/`reply[0..3]=`
   de cada comando, se `WARN_ON(1)` dispara (stack trace), e confirmação física do usuário (luz
   azul apaga + fan desliga, ou continua como antes).
5. Documentar resultado (sucesso = novo baseline oficial em `AGENTS.md`; falha = registrar o
   `reply` bruto do MCU capturado — dado nunca obtido antes, vira ponto de partida da próxima
   iteração em vez de continuar especulando às cegas sobre o payload).

### Rollback disponível
Tag `20260730-sata-polling-fase-ab` continua em `boot_referencia/` como baseline anterior — se o
teste do S5 causar qualquer regressão inesperada, `sudo ./deploy-boot-7.0.sh
20260730-sata-polling-fase-ab` volta ao estado confirmado (GBE + SATA funcionais).
