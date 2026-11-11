---
name: marco-2026-07-17-sky2baikal-pronto-teste
description: "MARCO fim de 2026-07-17: sky2 probou a GBE Baikal SEM crash mas 'unsupported chip type 0x0' — syscon mantém domínio de energia da GBE OFF por padrão; próximo passo: deploy da tag 20260717-iccdbg (já compilada, AGUARDANDO HD no PC) e mapear serviço ICC device-power via /proc/ps4_icc ao vivo"
metadata: 
  node_type: memory
  type: project
  originSessionId: dfd95c6f-d4a4-4437-929d-a734e0aa051c
  modified: 2026-07-18T21:04:18.127Z
---

**⟦ATUALIZADO 2026-07-18 — o teste da iccdbg JÁ FOI FEITO. A hipótese do ICC device_power está DESCARTADA. RETOMAR pela seção "PRÓXIMO PASSO 2026-07-18" no fim deste arquivo.⟧**

**DEPLOY JÁ FEITO (2026-07-18 ~0h): tag ativa no HD = `20260717-iccdbg`.** O teste do roteiro ICC abaixo foi executado e o resultado mudou o rumo — ver seção nova no fim. Causa raiz da saga stmmac: [[baikal-gbe-e-sky2-nao-stmmac]].

## Resultado do teste da tag `20260717-sky2baikal` (2026-07-17, noite)

- **SEM crash** — boot completo, DEBUG LOOP estável por 30+ iterações, WiFi/telnet normais. O Oops do stmmac sumiu como previsto.
- sky2 probou a GBE e falhou LIMPO: `sky2 0000:00:14.1: unsupported chip type 0x0` → `probe failed with error -95`. O registro B2_CHIP_ID (byte no offset 0x11a do BAR0) lê 0.
- Inspeção ao vivo via telnet (busybox sem applet devmem; usar `dd if=/dev/mem bs=4 count=1 skip=$(( (0xc2000000 + off) / 4 )) | od -An -tx4` — leituras MMIO de 32 bits dentro dos 4KB do BAR0 são SEGURAS, provado em 3 drivers/testes): o device NÃO está morto — vários registradores respondem valores reais (0x0→0x79498100, 0xB0→0x001f03ff) e alguns mudam entre leituras, mas o mapa não bate com um Yukon acordado.
- **CAUSA (psdevwiki, página Southbridge, saída do comando `devpm` do Syscon): o domínio de energia da GBE fica DESLIGADO por padrão** — `devpm` lista `# gbe off` (e `sdio off`; todo o resto on). O Orbis liga via ICC quando o usuário usa LAN com fio.
- Kernel 5.4 neocine (binário em `old_project/kernels/5.4.247-neocine/bzImage`; vmlinux/config extraídos com scripts do kernel) analisado: só tem o ID do AEOLIA_GBE (0x909e), nada de Belize/Baikal — **Ethernet nunca funcionou em Baikal/Pro em fork nenhum**; estamos abrindo caminho inédito.
- Comentário no `drivers/ps4/Makefile` da fail0verflow confirma: "drivers/net/ethernet/marvell/sky2 (implements ps4-gbe)".

## Roteiro da tag `20260717-iccdbg` (próximo teste, via telnet)

A tag adiciona `/proc/ps4_icc` (patch `patches/ps4-icc-proc-debug.patch`, arquivo novo `drivers/ps4/ps4-icc-debug.c`): `echo "major minor [bytes hex]" > /proc/ps4_icc` envia comando ICC (via apcie_icc_cmd, que despacha pro bpcie no Baikal); `cat /proc/ps4_icc` mostra ret+reply.

1. Sanity: `echo "2 6" > /proc/ps4_icc; cat /proc/ps4_icc` (query versão de firmware — comando sabidamente OK, copiado do do_icc_init).
2. Mapear device-power (major 5) com os minors GET primeiro (não mudam estado): `5 0x01` (wlan/bt, conhecido), `5 0x11` (usb), `5 0x21` (hdd?), `5 0x31` (bd?), **`5 0x41` (gbe? — alvo)**. Padrão extrapolado de resetUsbPort()/resetBtWlan() em `drivers/ps4/ps4-apcie-icc.c` (wlan set=0x00 val 3=on; usb set=0x10 val 1=on) e da lista `icc_device_power_*` da página IOCTL do psdevwiki (que expõe só wlan/usb/hdd/bd ao userland — gbe não é exposto no Orbis).
3. Ligar a GBE: provável `echo "5 0x40 01" > /proc/ps4_icc` (talvez o valor seja 1, talvez seja bitmask tipo o 3 do wlan/bt — testar 01 primeiro).
4. Verificar se acordou: `dd if=/dev/mem bs=4 count=1 skip=$(( 0xc2000118 / 4 )) | od -An -tx4` (esperar byte 0x11a != 0, um chip id Yukon real tipo 0xb5-0xbc) e então **reprovar o sky2 SEM reboot**: `echo 0000:00:14.1 > /sys/bus/pci/drivers/sky2/bind` → esperar "Yukon-2 ... chip revision" no dmesg → subir eth0.
5. Se 0x40/0x41 não for gbe: variar minors (0x50, 0x60...) — minor inválido só retorna erro/NAK, sem efeito colateral (protocolo request/reply com checksum).
6. Achando o comando certo: gravar em patch permanente (no bpcie glue init ou no probe ps4 do sky2) + reativar netconsole nos bootargs da tag seguinte.

## Estado dos artefatos (fim de 2026-07-17)

- **HD ficou no PS4** (desligado pelo usuário ao encerrar); tag ativa nele ainda é `20260717-sky2baikal`.
- Kernel `20260717-iccdbg` = sky2baikal + /proc/ps4_icc; bzImage/config/bootargs/initramfs prontos em `boot_referencia/`, símbolos verificados no System.map (14 hits). Bootargs SEM netconsole (proposital até a eth0 provar que sobe limpa).
- Os 2 patches (`sky2-baikal-gbe.patch`, `ps4-icc-proc-debug.patch`) aplicados na árvore e versionados; `00-build-kernel-7.0.sh` os aplica em loop idempotente.
- Builds com restrição de CPU: usuário pediu 1 núcleo e depois liberou 4 — lançar SEMPRE com `taskset -c 0-3` + `nice` desde o início ([[taskset-kbuild-recursivo-limitar-desde-o-inicio]]); perguntar antes de voltar a 8.
- Fallbacks: `wifissh` (sabidamente bom) ou `20260717-sky2baikal` (boota estável, sem Ethernet).

## PRÓXIMO PASSO 2026-07-18 (SUPERADO em 2026-07-20 — ver nota abaixo)

> ⚠️ **SUPERADO 2026-07-20:** o plano de varredura ao vivo descrito nesta seção foi abandonado. Além de ter se provado perigoso (block-read na região pervasive desligou o console — ver aviso de segurança abaixo), agora temos o **dump completo e descriptografado do kernel Orbis 12.52** (`consolidado/dumps_orbis/kmem_dump_1252.bin`, 32.2MB, extraído com sucesso em 2026-07-20). O driver GBE real da Sony (`SceGbeMtsCtrl`/`icc_power.c`) está lá dentro — o próximo passo real é reverse-engineering estático desse binário (disassembly da rotina de power-on da GBE), não mais sondagem cega de hardware. Ver `consolidado/BAIKAL_HARDWARE_DISCOVERIES.md` seção 1 (reescrita) para o estado atual consolidado.

## Resultado do teste iccdbg (histórico, ainda válido como registro do que já foi descartado)

O roteiro ICC acima FOI executado. **Descartou a hipótese `5 0x40/0x41 = gbe`:** `5 0x41` (e toda a varredura `5 0x51..0xf1`) retorna `01 05` = NAK, idêntico a um minor inválido (`5 0x03`). O serviço `icc_device_power` do EMC tem só 4 dispositivos (wlan/bt, usb, hdd, bd — bate com a página IOCTL do psdevwiki). **GBE não se liga por ICC device_power.**

Caracterização MMIO ao vivo (segura): B2_CHIP_ID (0x11b), B2_MAC_CFG (0x11a) e B0_CTST (0x004) leem 0, mas 0x000/0x008 leem valores reais estáveis → **MAC core Yukon com clock/power gated atrás de um wrapper PCIe ligado**; gate externo ao MAC (sky2_init roda o clock-enable padrão e não acorda). É uma rail do **Syscon** (`devpm: gbe off`).

**AÇÃO no próximo boot:** varrer ao vivo (leitura `/dev/mem` é SEGURA, inclusive em rajada — provado, não travou) a região **pervasive do bpcie glue** procurando o clock/reset-gate da GBE. Dados prontos (do dmesg): glue = função **00:14.4**, BAR2 pervasive = **0xc8800000**–0xc89fffff (2MB). Referência viva: USB/SATA são acordados em `BAR2 + 0x180000` = **0xc8980000** (ver `bpcie_baikal_sata_phy_init` em `ps4-bpcie.c`, escreve pulse/hold). Procurar registrador análogo da GBE noutro offset da mesma região. Comando de leitura no PS4: `dd if=/dev/mem bs=4 count=1 skip=$(( 0xADDR / 4 )) | od -An -tx4`.

**Fallbacks/alternativas se a pervasive não revelar:** (a) achar outro serviço ICC que o EMC use pra pedir a rail ao Syscon; (b) byte de config na NVS (`offset 0x38` = "gbe related") lido no boot — **NVS write pode BRICKAR, só com autorização explícita do usuário.** Detalhe completo: TENTATIVAS_7.0.md item 13 e [[baikal-gbe-e-sky2-nao-stmmac]].

**Segurança revista:** varredura MMIO em rajada da janela de 4KB da BAR0 (0xc2000000) é SEGURA. **MAS block-read da região pervasive (0xc8800000+, BAR2 do glue) DESLIGA o PS4** — comprovado 2026-07-18: `dd bs=128` em 0xc8940000 (offset 0x140000) desligou o console; leitura de 1 palavra em offsets 64KB era segura, mas ler > offset 0 num bloco ativo bate em registrador veneno → watchdog Syscon. **Blind-scan do pervasive é técnica MORTA.** Ver [[baikal-gbe-toque-trava-desliga-ps4]].

**Blocos pervasive já mapeados (leituras de 1 palavra, seguras):** ativos = 0x100000(f570c001), 0x140000(10206333), 0x160000(62003532), 0x170000(000b0331), 0x180000(0x1=USB power ref); não-mapeados (ffffffff) = 0x120000/0x130000/0x190000+; zerados = 0x110000/0x150000; low half 0x00000–0xf0000 lê 0x00511148 uniforme (aliasing provável). Não continuar sondando isso às cegas — próxima abordagem precisa de referência externa (kernel Orbis Baikal / datasheet Marvell), não tentativa e erro no hardware.

## Pendências que continuam abertas (independentes deste marco)

- GPU `ring gfx test failed (-110)` em todo boot — deprioritizado a pedido do usuário.
- SSH automático no initramfs de debug (pedido do usuário; script fonte do initramfs ainda não localizado).
- `LICOES_APRENDIDAS.md` sem caminho canônico pós-reorganização (ver [[ler-licoes-aprendidas-primeiro]]).
- Bugs conhecidos do caminho de imagem completa `01-build-image-7.0.sh`/`02-burn-image-7.0.sh` (não usado).
