# Teste Telnet — eth0 na Subnet Correta — 2026-07-23 (noite, pós-reboot)

## Contexto

Testes anteriores desta sessão usaram `ping -I eth0 192.168.6.100` (subnet WiFi,
`192.168.6.0/24`). Mas `eth0` na verdade recebe IP `192.168.0.2` via DHCP/config
estático do initramfs — **subnet totalmente diferente** (`192.168.0.0/24`), a
mesma usada pelo netconsole (`CLAUDE.md`: "IP PS4 192.168.0.2 -> Host PC
192.168.0.1:6666/UDP"). Ou seja, **nenhum teste anterior de ping validou o eth0
de fato** — a resposta sempre veio pelo `wlan0`.

## Estado do Driver Após Fixes do Usuário

Diff aplicado em `drivers_mts/mts.c` (confirmado via `git diff` antes do teste):
- RX init com `OWN=1` (buffer vazio, pronto pra HW) — coerente com TX
- Condição de `mts_rx_clean()` corrigida: `if (ctl & MTS_DESC_OWN) break;`
  (quebra quando vazio, processa quando HW limpou OWN) — **lógica agora
  simétrica e coerente com TX**, sem loop infinito
- Debug log condicional em `mts_rx_clean()` (bug de throttling: reimprime a
  cada poll de 16ms porque `cleaned` sempre começa em 0 — não é infinito, só
  verboso demais)
- Tail pointer TX e RX (`0x3c`/`0x40`) sendo escritos após submissão/reclamação
- Atributo sysfs `mts_regs` novo, funcionando (`cat
  /sys/class/net/eth0/device/mts_regs`)

## Teste 1: Estado Pós-Boot Limpo

```
lsmod | grep mts   → (vazio, driver não carregado)
ip addr show       → só lo, tunl0, wlan0 (192.168.6.128/24), ap0, ap1
```

Confirmado: boot limpo, sem `mts` residual travado (diferente do estado anterior
ao reboot, que tinha o módulo preso em "Unloading").

## Teste 2: Carregar Driver Novo

```bash
cd /tmp && wget -q http://192.168.6.100:8000/mts.ko -O mts.ko   # OK, 916000 bytes
insmod /tmp/mts.ko stage=4
```

Console NÃO travou. Conexão telnet caiu por timeout (comando demorado), mas
ping ao WiFi seguiu respondendo normalmente — não foi crash.

## Teste 3: dmesg do Carregamento (sequência completa relevante)

```
[127.625] aneis: TX va=... dma=0x010dd000 | RX va=... dma=0x010de000 | bufs dma=0x1180000 (384 KB)
[127.627] aneis programados: TX base/ptr=0x010dd000 RX base/ptr=0x010de000
[127.627] MAC enable: 0x34=0x00000001 0x38=0x00000000 0x50=0x00000020 0x70=0x0001c040
[127.629] PHY calibration: iniciando...
[127.631] Glue PERVASIVE_CLOCK_PULSE (0x10a030) antes: 0x000016c9
[127.647] Glue PERVASIVE_CLOCK_PULSE (0x10a030) depois: 0x000016c9
[127.663] Enviando pulso de liberação de reset no Glue GBE pulse (0x180074)...
[127.735] Status antes wakeup: 0x0000
[127.736] Enviando soft-reset ao PHY (devad=1, reg=0x0000, val=0x8000)...
[127.951] Limpando reset e power-down bits...
[128.575] Status depois wakeup (reg 0x0000): 0x0000 (ret=0)
[128.576] PHY Regs: Status1=0x0000 ID1=0x0000 ID2=0x0000
[128.577] ⚠️ PHY ainda retorna zeros (powered-down persiste)
[128.578] MDIO diagnosis: testing Clause 45 vs Clause 22...
[128.694] Clause 45: ret=0 val=0x0000
[128.695] Clause 22: ret=-110 val=0xffff
[128.696] ✅ PHY responds to Clause 45, continuing normal path
[128.697] PHY calibration: BAR2 params: 0x6c=0x331250b5 0x68=0x000050b4 0x60=0x000050a4 0x5c=0x33125095 0x100=0x10000201
[133.247] IMR (0x54) = 0x00000000
[133.248] MAC lido da SPM: 2c:cc:44:3f:69:5f
[133.249] mts registrado como eth0, MAC 2c:cc:44:3f:69:5f
[133.253] open (stage=4) carrier=1 rx=1 tx=1
[133.257] eth0 configurada 192.168.0.2
[133.268] Link DOWN (val=0x00000b78)
   ... (RX_CLEAN spam a cada 16ms, idx=0 sempre, cleaned=0) ...
[135.044] Link UP: 1000 Mbps Half duplex
```

## Teste 4: Estado Após ~15s de Uptime (via sysfs mts_regs)

```
=== BAR0 Registradores-chave ===
  +0x000 = 0x00000010
  +0x004 = 0x00000b19
  +0x034 = 0x00000000   <- MAC_EN1 (comentário no código diz "não retém valor, normal")
  +0x038 = 0x00000000   <- MAC_EN2 (comentário esperava 0x08 em sessões anteriores!)
  +0x050 = 0x00000084
  +0x054 = 0x00000000   <- IMR, todas IRQs mascaradas (esperado, NAPI via timer)
  +0x05c = 0x00101000
  +0x070 = 0x00010040
  +0x07c = 0x017d7840

=== Contadores HW (clear-on-read) ===
  MTS_CNT_PKTS   = 0
  MTS_CNT_BYTES  = 0
  MTS_CNT_PKTS2  = 0
  MTS_CNT_BYTES2 = 0

=== Estado dos aneis (SW) ===
  tx_idx=19  tx_clean=19  rx_idx=0   (19 TX enviados em sessão anterior de boot? não, zerado no load — deve ser de pings de teste ANTES desta leitura, não documentados aqui)

RX[000..003] e RX[253..255]: todos ctl=0x80000600 (OWN=1, vazio) — nenhum avançou
Hexdump RX[000]/RX[001]/RX[255]: todos zeros — nenhum dado físico chegou aos buffers
```

## Teste 5: Ping Direto na Subnet Correta (192.168.0.0/24)

**Do host (`192.168.0.1`, interface `enp60s0`) para `192.168.0.2` (eth0 do PS4):**

```
PING 192.168.0.2: 5 pacotes transmitidos, 0 recebidos, +3 erros, 100% packet loss
De 192.168.0.1 icmp_seq=1 Host de destino inalcançável   (x3)
```

```
arp -a | grep 192.168.0
  ? (192.168.0.2) at <incomplete> on enp60s0     <- ARP nunca resolveu
```

**Carrier físico do lado do host:**
```
/sys/class/net/enp60s0/carrier = 1       (link físico detectado)
/sys/class/net/enp60s0/speed   = 1000
/sys/class/net/enp60s0/duplex  = full
```

## 🔴 Achado Crítico: Mismatch de Duplex

- **PS4 (eth0):** negocia e reporta **"Link UP: 1000 Mbps Half duplex"**
- **Host (enp60s0):** negocia **Full duplex** a 1000Mbps

**Por que isso importa:** o padrão IEEE 802.3ab (1000BASE-T) define apenas modo
**full-duplex** — half-duplex a 1000Mbps não é suportado pela imensa maioria dos
PHYs/switches modernos e normalmente indica que a autonegociação do lado do PS4
não completou corretamente (ou que o driver está decodificando errado o
registrador de link status). Esse tipo de mismatch classicamente causa:
- Frames TX do PS4 chegam ao host (explica por que TX "funciona" com 95% de
  sucesso — pode ser broadcast/half-duplex tolerando saída, embora sujeito a
  colisão)
- Frames RX vindos do host podem ser descartados silenciosamente na camada
  MAC/PHY do PS4 antes mesmo de chegar ao DMA — explicando `MTS_CNT_PKTS=0`
  mesmo com ARP requests sendo enviados pelo host repetidamente

## 🟡 Achado Secundário: MAC_EN2 (0x38) não retém 0x08 nesta sessão

Comentário no código (`mts_mac_enable()`, linha 983-985) documenta observação de
sessão anterior: "escrito 1, lê 8" em 0x38. Nesta sessão, `0x38` ficou em
`0x00000000` tanto no log de carregamento quanto ~15s depois via sysfs. Pode ser:
- Variação normal entre boots (mencionado no comentário como não-crítico)
- Regressão real ligada ao problema de duplex/PHY acima (calibração de PHY
  reportou "PHY ainda retorna zeros" antes do Link UP aparecer)

Não still conclusivo — precisa de mais uma leitura em sessão limpa para
comparar.

## 🟢 Confirmado: RX Loop Não é Mais Infinito

A correção da condição OWN (`if (ctl & MTS_DESC_OWN) break`) eliminou o bug dos
22M pacotes. Agora o comportamento é coerente: `rx_idx` fica parado em 0 porque
nenhum frame real chegou — consistente com o mismatch de duplex acima, não um
bug de lógica do driver.

## 🟡 Bug Cosmético: Spam de Log RX_CLEAN

Condição `if (cleaned < 10 || cleaned % 1000 == 0)` reimprime a cada chamada do
timer de poll (16ms) porque `cleaned` é local à função e sempre começa em 0.
Não afeta funcionalidade, mas polui a tela/dmesg. Precisa de um flag
estático/rate-limit real se for mantido como diagnóstico permanente.

## Pendências para Próximo Plano

1. **Investigar a negociação de duplex** — por que o PS4 fecha em Half duplex
   a 1000Mbps. Pode envolver revisar a tabela de calibração do PHY
   (`mts_phy_calibration()`) ou a leitura/decodificação do registrador de link
   status (0x004, valores vistos: `0x00000b19` estável, `0x00000b78` durante
   transição DOWN).
2. **Testar forçar full-duplex** (se o PHY/registrador expuser esse controle)
   ou testar com um switch Gigabit real no meio (em vez de host-to-host direto)
   para ver se a negociação muda.
3. **Corrigir o throttling do log de debug** em `mts_rx_clean()` antes de deixar
   como diagnóstico permanente.
4. **Re-testar RX assim que duplex for resolvido**, usando sempre
   `192.168.0.1 ↔ 192.168.0.2` (subnet real do eth0) — nunca mais usar
   `192.168.6.x`/WiFi como proxy de teste do eth0.
5. Entender por que `MTS_MAC_EN2 (0x38)` não reteve `0x08` nesta sessão —
   comparar com uma nova leitura limpa.

## Commits/Estado

Nenhum commit novo ainda — mudanças em `drivers_mts/mts.c` continuam não
commitadas (`git status` mostra `modified: drivers_mts/mts.c`). Aguardando
definição do próximo plano antes de commitar, já que o RX ainda não está
funcional (só está logicamente coerente agora).
