# Plano: Implementar TX real, RX real e Carrier Detection no driver `mts.c`

## Contexto

O driver `mts.ko` (GBE Baikal, `drivers_mts/mts.c`/`mts.h`) já está em produção e estável no
kernel 7.0 do projeto: registra `eth0` com MAC real lido da SPM, aloca e programa corretamente
os anéis DMA (TX/RX, 256 descritores de 16 bytes), habilita o MAC (`stage=4` é o default) e o
bus master já está ligado — zero Kernel Panics em todos os testes ao vivo até hoje. As três
lacunas conhecidas (ver `memory/mts-driver-stage4-incompleto-e-srcversion-mismatch.md`) são:

1. `mts_start_xmit()` descarta 100% dos pacotes (`tx_dropped++`) — TX nunca foi implementado.
2. `mts_open()` chama `netif_carrier_off()` incondicionalmente e nada nunca chama
   `netif_carrier_on()` — a interface fica `NO-CARRIER` para sempre, mesmo com cabo conectado.
3. `mts_interrupt()` só incrementa um contador — não existe consumo do anel RX nem NAPI.

O objetivo desta sessão é fechar essas três lacunas para a Ethernet cabeada funcionar de ponta
a ponta (`ping`/DHCP através do cabo).

### Descobertas novas desta sessão (engenharia reversa, ainda não documentadas no projeto)

Decompilando (r2ghidra) mais funções do driver original Sony `if_mts.c` a partir do dump
`kmem_dump_1252.bin`:

- **`BAR0+0x04` é o registrador de status de link** (`fcn.ffffffffdc5a2bd0`, nunca catalogado
  antes — o mapa de registradores pulava de `0x00` MDIO direto para `0x08`). Bit 0 = link up,
  bits `[3:2]` = velocidade (0=10M/1=100M/2=1000M), bit 6 = full duplex.
- **Semântica unificada do bit OWN**, resolvendo a ambiguidade que constava na memória do
  projeto: `OWN==1` sempre significa "pronto para o software agir"; `OWN==0` sempre significa
  "em posse do hardware". Para TX: descritores começam com OWN=1 (ociosos), o driver preenche
  os campos e **limpa** OWN por último para entregar ao hardware; quando a transmissão termina,
  o hardware **seta** OWN=1 de volta (confirmado por `fcn.ffffffffdc5a2d00`, a rotina de
  reclamação de TX do Orbis, que faz exatamente essa checagem). Para RX, a mesma regra já está
  implementada corretamente em `mts_setup_rings()` — não precisa mudar.
- **Não existe registrador de doorbell/kick em lugar nenhum da BAR0** (mapeamento 100%
  completo, `memory/GBE-VIVA-driver-errado-mts-nao-sky2.md`). A limpeza do bit OWN já É o kick —
  o hardware faz polling contínuo do anel (evidenciado pelo próprio `MTS_TX_RING_PTR`/
  `MTS_RX_RING_PTR` avançando sozinhos).
- Bits de descritor TX (`fcn.ffffffffdc5a5ae0`): bit 31=OWN, bit 30=WRAP (já em `mts.h`), bit
  29=SOP (start of packet), bit 28=EOP (end of packet), bits `[10:0]`=comprimento (mesma
  máscara `MTS_DESC_LEN_MASK` já usada por RX). MTU padrão (1500) cabe folgado em 0x7ff, então
  **não é necessária fragmentação multi-descritor** no MVP.
- **`CONFIG_MTS_GBE=m` confirmado no `.config`** — `mts` é módulo tristate real
  (`obj-$(CONFIG_MTS_GBE) += mts.o`), carregável via `insmod`/`rmmod` sem precisar de reboot
  completo do console. Isso barateia bastante a iteração de testes ao vivo (só panics exigem
  power cycle).

Não é necessário implementar checksum offload, VLAN ou fragmentação multi-descritor nesta
primeira fase — o objetivo é TX/RX/carrier mínimos e corretos.

## Arquivos a modificar

- `drivers_mts/mts.h` — novos defines (`MTS_LINK_STATUS`, bits de link, `MTS_DESC_SOP/EOP`) e
  novos campos em `struct mts_priv`.
- `drivers_mts/mts.c` — nova lógica em `mts_open()`/`mts_stop()`/`mts_probe()`/`mts_remove()`,
  três funções novas (`mts_link_check()`, `mts_rx_clean()`+`mts_poll()`,
  `mts_tx_reclaim()`+`mts_start_xmit()` reescrito), timer de polling, NAPI, `.ndo_tx_timeout`.
- Sincronizar as mesmas mudanças em
  `/mnt/hdauxiliar/temp/kernel_build_7.0/drivers/net/ethernet/sony/{mts.c,mts.h}` (a árvore de
  build ativa — precisa ser idêntica para o `srcversion`/`Module.symvers` baterem, ver
  `memory/mts-driver-stage4-incompleto-e-srcversion-mismatch.md`) antes de qualquer rebuild do
  módulo.

## Arquitetura de polling

NAPI (`netif_napi_add`/`napi_schedule`) disparado por um `timer_list` de software — não um timer
cru chamando `netif_rx()` direto. Não há registrador de status de IRQ localizado, então o
polling é "puro por software": o timer chama `napi_schedule()` a cada tick (`poll_interval_ms`,
default 10ms); `mts_poll()` processa RX + reclamação de TX e decide quando completar
(`napi_complete_done`). Ganha de graça: contexto de softirq seguro para alocação de skb,
integração limpa com `napi_disable()` em `ndo_stop`, e caminho fácil para acoplar uma IRQ real
depois, se o registrador de status for localizado. Um único timer cuida de RX + reclamação de
TX + carrier check (carrier check é uma leitura de registrador, desprezível em custo).

## Mudanças concretas

### `mts.h`
```c
#define MTS_LINK_STATUS       0x04
#define MTS_LINK_UP           BIT(0)
#define MTS_LINK_SPEED_MASK   (0x3 << 2)
#define MTS_LINK_SPEED_10     (0x0 << 2)
#define MTS_LINK_SPEED_100    (0x1 << 2)
#define MTS_LINK_SPEED_1000   (0x2 << 2)
#define MTS_LINK_DUPLEX_FULL  BIT(6)

#define MTS_DESC_SOP          BIT(29)
#define MTS_DESC_EOP          BIT(28)
```
Em `struct mts_priv`, adicionar: `tx_clean` (consumidor de reclamação TX), `tx_skb[]`/
`tx_skb_dma[]` (arrays `kcalloc(MTS_RING_SIZE, ...)` mapeando índice→skb pendente),
`struct napi_struct napi`, `struct timer_list poll_timer`, `bool napi_enabled`,
`link_last_raw`/`link_up`/`link_speed`/`link_duplex`.

### `mts_link_check()` (nova)
Lê `MTS_LINK_STATUS`, só age se o valor mudou desde a última leitura (`link_last_raw`), decodifica
bit0/bits`[3:2]`/bit6 e chama `netif_carrier_on()`/`netif_carrier_off()`. Em `mts_open()`, setar
`link_last_raw = ~0U` antes da primeira chamada para garantir que a primeira leitura sempre
dispare a notificação.

### `mts_rx_clean(mp, budget)` + `mts_poll(napi, budget)` (novas)
Para cada descritor a partir de `rx_idx`: se `OWN` não está setado, para (nada novo). Senão, lê
o comprimento (`ctl & MTS_DESC_LEN_MASK`), aloca skb (`napi_alloc_skb`), copia de
`rx_buf + rx_idx*MTS_RX_BUF_SIZE` (sem necessidade de `dma_sync`, é `dma_alloc_coherent`),
`eth_type_trans` + `napi_gro_receive`, e devolve o descritor ao hardware limpando OWN (mantendo
WRAP se for o último índice). `d[1]` (endereço do buffer) nunca precisa ser reescrito — o pool é
fixo. `mts_poll()` chama `mts_tx_reclaim()` e depois `mts_rx_clean()`.

### `mts_tx_reclaim(mp)` + `mts_start_xmit()` reescrito
Reclamação: percorre de `tx_clean` até `tx_idx` enquanto o descritor tiver `OWN` setado (=
transmissão concluída), desmapeia (`dma_unmap_single`) e libera (`dev_consume_skb_any`) o skb
pendente, restaura `d[2] = 0xffff0000` (padrão ocioso), acorda a fila se estava parada.
Transmissão: checa se o descritor produtor atual tem `OWN` setado (livre); se não, `netif_stop_queue`
+ `NETDEV_TX_BUSY`. Senão, `dma_map_single(skb->data, skb->len)`, escreve endereço em `d[1]`,
`d[2]=0xffff0000`, monta `ctl = len | SOP | EOP | (WRAP se último índice)`, `wmb()`, e só então
escreve `d[0] = ctl` (sem o bit OWN — essa limpeza É o kick). Avança `tx_idx`, tenta reclamação
oportunista, para a fila se o próximo descritor não estiver livre.

### Fiação (`mts_probe`/`mts_open`/`mts_stop`/`mts_remove`) + module params
Novos params seguindo o padrão de `stage`/`force_mac_reset`, todos `0644` (reconfiguráveis via
sysfs sem `rmmod`): `enable_carrier`, `enable_rx`, `enable_tx` (todos default `false`),
`poll_interval_ms` (default 10). `mts_probe()` aloca `tx_skb[]`/`tx_skb_dma[]`, registra NAPI e o
timer. `mts_open()` liga carrier check/NAPI/timer conforme os flags e só chama
`netif_start_queue()` se `enable_tx`. `mts_stop()` desliga timer, `napi_disable`, reclama e
força drenagem de qualquer skb pendente (novo `mts_tx_drain_force()`, sem checar OWN pois o MAC
já foi parado), evitando vazamento em ciclos repetidos de teste. Adicionar
`.ndo_tx_timeout = mts_tx_timeout` a `mts_netdev_ops` (hoje `watchdog_timeo` está setado mas sem
handler).

## Ordem de implementação e teste ao vivo

Implementar tudo de uma vez no código (os três recursos + scaffolding), mas expor cada um atrás
de um module param independente (`enable_carrier`/`enable_rx`/`enable_tx`, default `false`), e
ativar em fases progressivas via sysfs — sem precisar recompilar/`rmmod` entre fases:

1. **Fase A — scaffolding neutro (risco ~zero):** carregar o `.ko` novo com todos os `enable_*`
   em `false`. Objetivo: confirmar que compila/carrega sem panics, que `rmmod mts` funciona de
   forma limpa (nunca testado antes — estabelece se o Nível 2 de iteração, `rmmod`+`insmod`, é
   seguro neste hardware), e que o comportamento observável não mudou (baseline).
2. **Fase B — carrier + RX (leitura passiva, nenhuma escrita nova em registrador de controle):**
   ativar `enable_carrier`, testar com cabo conectado e desconectado (dois sub-testes, valida a
   polaridade dos bits do registrador `0x04` pela primeira vez ao vivo). Depois ativar
   `enable_rx`, gerar tráfego do lado do host (`ping`/`arping`), conferir `ip -s link show eth0`
   e `dmesg`. Cross-check independente: ler manualmente os contadores clear-on-read
   `0x100/0x104` (`MTS_CNT_PKTS`/`MTS_CNT_BYTES`, não tocados pelo driver) antes/depois de uma
   rajada de pings — servem de oráculo isolado. `tcpdump` no host para correlacionar.
3. **Fase C — TX (primeira escrita real em campo de descritor):** só depois da Fase B validada.
   Ativar `enable_tx`, `ping` do lado do PS4 primeiro com poucos pacotes, checar `tcpdump` no
   host, `dmesg` (sem `tx_timeout`/`tx_dropped` inesperado), `ip -s link show eth0` TX
   crescendo. Só then testar tráfego sustentado maior.

Cada mudança de estado (`enable_*`, `up`/`down`, `insmod`/`rmmod`) ao vivo no console real
precisa de autorização explícita do usuário antes de ser executada, mesmo sendo de baixo custo
— só compilação e leitura de código acontecem sem autorização. Documentar cada resultado de
teste imediatamente em `memory/` (regra de atualização contínua do `CLAUDE.md`).

## Verificação

Não é possível compilar/rodar o kernel real neste ambiente de planejamento — a validação
funcional acontece ao vivo no PS4, na sequência de fases acima. Antes disso, verificação
estática possível:
- Ler o diff final lado a lado com `consolidado/MTS_INIT_SEQUENCE_dc5a31f0.md` e
  `consolidado/decompiled_dc5a5ae0.txt`/`decompiled_dc5a2d00.txt`/`decompiled_dc5a2bd0.txt` para
  confirmar que os bits/offsets usados no código batem com a RE.
- Conferir que `drivers_mts/` e a árvore de build (`kernel_build_7.0/drivers/net/ethernet/sony/`)
  ficam idênticas (`diff`) antes de qualquer rebuild do módulo.
- Build do módulo (`make LLVM=1 ARCH=x86_64 M=drivers/net/ethernet/sony modules` dentro da
  árvore `kernel_build_7.0`) exige autorização explícita do usuário antes de rodar (regra crítica
  #6 do `CLAUDE.md`: proibido rodar `make`/build sem confirmação prévia).
