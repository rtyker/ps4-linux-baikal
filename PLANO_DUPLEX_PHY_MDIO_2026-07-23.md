# Plano: Diagnóstico de Duplex/PHY e Correção de Log — driver `mts.ko`

## Contexto

TX e a lógica de software do RX já estão corrigidos e commitáveis: o bit
`MTS_DESC_OWN` tem semântica simétrica confirmada entre TX e RX (OWN=1 =
"buffer vazio, hardware pode escrever"; hardware limpa OWN=0 ao entregar),
tail pointers (`0x3c`/`0x40`) funcionando, e o antigo bug de loop infinito de
RX (22M pacotes) foi eliminado corrigindo a condição de `break` em
`mts_rx_clean()`.

Mesmo assim, **nenhum frame chega fisicamente ao `eth0`**: testado na subnet
correta (`192.168.0.1` host ↔ `192.168.0.2` PS4, cabo CAT6 direto porta a
porta, confirmado pelo usuário como configuração adequada — gigabit em ambas
as pontas). `MTS_CNT_PKTS` (contador de hardware clear-on-read) fica em 0,
buffers RX ficam zerados, `rx_idx` nunca avança.

O dado mais importante encontrado nesta sessão: o dmesg mostra que a tentativa
do driver de **forçar** full-duplex+link-up escrevendo em `MTS_LINK_STATUS`
(BAR0+0x04, `mts.c:818-821`) é **NO-OP confirmado** — `pre 0x04=0x00000b78` /
`post 0x04=0x00000b78`, valores idênticos antes/depois da escrita. Ou seja, é
um registrador de status real de hardware, não gravável para forçar estado.
A transição real (não a escrita forçada) fez o link subir em
**"Link UP: 1000 Mbps Half duplex"** — tecnicamente não-padrão, já que
1000BASE-T (IEEE 802.3ab) só define autonegociação full-duplex. Isso é o
suspeito nº1 de por que nenhum frame chega (fora do escopo: se for confirmado
que não é isso, o suspeito nº2 já identificado é `MTS_MAC_EN2`/0x38 lendo
`0x00000000` nesta sessão, quando uma nota antiga no código esperava `0x08`).

Nunca houve, até hoje, uma releitura dos registradores PHY padrão (Clause 45,
MMD=1 PMA/PMD) **depois** que o link sobe — as únicas leituras desses
registradores acontecem durante o wakeup inicial do PHY (`mts.c:791-822`,
ainda com o PHY "retornando zeros/powered-down"), nunca depois do
`mts_link_check()` (`mts.c:998-1044`) reportar link up. Esse é o buraco que
este plano fecha: ter uma fonte de verdade independente da decodificação
atual do bit6 de `MTS_LINK_STATUS`.

Também há um bug cosmético confirmado: o log `RX_CLEAN` em `mts_rx_clean()`
(`mts.c:1123-1134`) reimprime a cada tick do timer de poll (a cada poucos ms)
porque a variável `cleaned` é local à função e sempre começa em 0 — a condição
`cleaned < 10` dispara em toda chamada, gerando spam visível na tela do PS4
mesmo sem tráfego algum.

Decisões de escopo já confirmadas com o usuário:
- Sem switch Gigabit disponível para teste de topologia agora — cabo CAT6
  direto, porta a porta, ambas gigabit. Não há teste físico alternativo a
  fazer nesta rodada; se o diagnóstico confirmar half-duplex genuíno, a
  prioridade passa a ser investigar a autonegociação/calibração do PHY em vez
  de sugerir troca de topologia.
- Não mexer nas sequências de calibração PHY vendor-specific
  reverse-engenheiradas (`mts_phy_calibration`, `mts.c:551-968`, valores tipo
  `0x39001e`) — são RE do binário Orbis, fora de escopo deste plano.
- Sem necessidade de reboot completo do console entre iterações — RX/PHY é
  só leitura/diagnóstico; `rmmod`/`insmod` via telnet já é o fluxo padrão
  usado nesta sessão.

---

## Fase A — Corrigir bug de throttling do log `RX_CLEAN`

**Arquivo:** `drivers_mts/mts.c:1118-1175` (`mts_rx_clean`).
**Arquivo:** `drivers_mts/mts.h` (`struct mts_priv`, perto de `link_last_raw`/`irq_count`).

Adicionar campo persistente `u32 rx_debug_logs;` em `struct mts_priv`
(`mts.h`). Trocar a condição da linha 1128 de `cleaned < 10` para
`mp->rx_debug_logs < 10`, incrementando `mp->rx_debug_logs++` dentro do bloco
de log (mantendo o `% 1000`, mas agora contando pacotes processados ao longo
da vida do driver, não chamadas do timer). Isso preserva a visibilidade das
primeiras 10 ocorrências reais e a amostragem a cada 1000, sem spammar
quando não há tráfego algum.

**Critério de sucesso:** após recarregar sem tráfego, dmesg fica silencioso
(sem `RX_CLEAN` repetindo a cada poucos ms).

---

## Fase B — Estender `mts_regs_show()` com leitura PHY Clause 45 ao vivo

**Arquivo:** `drivers_mts/mts.c:1328-1440` (`mts_regs_show`).

Adicionar uma nova seção no sysfs (logo após o bloco "BAR0 Registradores-chave",
antes dos contadores HW) que lê ao vivo, via `mts_mdio_read()` já existente
(`mts.c:156-172`), os registradores padrão IEEE 802.3 Clause 45:

- `devad=0x01, reg=0x0000` — PMA/PMD Control1
- `devad=0x01, reg=0x0001` — PMA/PMD Status1
- `devad=0x01, reg=0x0002` — PMA/PMD ID1
- `devad=0x01, reg=0x0003` — PMA/PMD ID2
- `devad=0x07, reg=0x0001` — AN (Auto-Negotiation) Status — bit2=link,
  bit5=AN complete
- `devad=0x07, reg=0x000a` — 1000BASE-T AN Status (best-effort; se o PHY não
  suportar, reportar "N/A" sem quebrar o resto da função)

Cada leitura deve checar o retorno de `mts_mdio_read()` e reportar
`"timeout"` em vez de abortar caso dê `-ETIMEDOUT`. Reaproveitar o padrão de
`scnprintf` já usado no resto de `mts_regs_show()`. Também rotular os offsets
`0x034`/`0x038` já existentes no array `regs_key[]` (linha 1342) como
`MAC_EN1`/`MAC_EN2` no output, para leitura mais fácil sem decorar offsets
(mudança cosmética, mesma função, mesmo risco trivial).

Sem escritas novas — só leituras MDIO, protocolo já em produção
(`mts_mdio_read`), sem efeito colateral esperado na negociação de link. Sem
lock necessário (nenhum outro caminho ativo toca `MTS_MDIO` após o probe;
registrar como dívida técnica se um polling periódico de PHY for adicionado
no futuro).

**Critério de sucesso:** `cat /sys/bus/pci/devices/0000:00:14.1/mts_regs`
retorna a nova seção sem travar, com `ret=0` em pelo menos ID1/ID2.

---

## Fase C — Teste ao vivo: reload + aguardar Link UP + comparar

Usar o script já existente `./scripts/deploy_mts.sh` (push/test) — já
automatiza exatamente o fluxo necessário (rmmod, wget, insmod stage=4, depois
`cat mts_regs` → configura eth0 → ping → `cat mts_regs` de novo → dmesg).

1. `sudo scripts/build_mts_module.sh` (recompila com as mudanças da Fase A+B).
2. `./scripts/deploy_mts.sh push` (recarrega o módulo no PS4).
3. `./scripts/deploy_mts.sh test` (configura `eth0 192.168.0.2`, faz ping
   para `192.168.0.1`, captura `mts_regs` antes/depois + `RX_CLEAN` + dmesg).
4. Conferir no dmesg capturado que `"Link UP: 1000 Mbps ... duplex"` já
   apareceu antes da segunda leitura de `mts_regs` (o script já dá `sleep 4`
   entre elas, deve ser suficiente).
5. Extrair da saída: valor decodificado hoje do bit6 de `MTS_LINK_STATUS`
   ("Half duplex") lado a lado com os registradores Clause 45 novos (Fase B).

**Critério de sucesso:** ter as duas leituras (MAC status vs. PHY nativo)
lado a lado para decidir o fork da Fase D.

---

## Fase D — Fork de decisão

**D1 — PHY nativo confirma full-duplex real** (Clause 45 MMD=7/0x000a ou
Status1 divergindo do bit6 de 0x04):
→ Bug é de leitura/decodificação do registrador MAC de status, não duplex
real. Não mexer mais em duplex. Redirecionar investigação para
`MTS_MAC_EN2` (0x38) ficar em `0x00000000` (suspeito nº2) — comparar valor
pós-link contra o log do probe (`mts.c:987`), revisar se há dependência de
ordem entre `MTS_MAC_EN1`/`MTS_MAC_EN2` ainda não capturada. Isso vira o
próximo plano (fora de escopo aqui).

**D2 — PHY nativo também confirma half-duplex genuíno:**
→ Sem switch disponível para testar variável de topologia (confirmado pelo
usuário). Como CAT6 + gigabit nas duas pontas descarta problema óbvio de
cabo, a hipótese que sobra é autonegociação/calibração do PHY do lado do
driver (`mts_phy_calibration`) resolvendo incorretamente ou incompletamente.
Próximo passo (fora de escopo deste plano, vira plano novo): investigar
forçar duplex/velocidade via registrador BMCR do PHY (Clause 22, reg 0) ou
revisar a sequência de calibração vendor-specific em busca de um passo que
falte após o wakeup — isso é RE adicional, maior escopo, não iniciar sem
plano dedicado.

---

## Riscos e observações

- Nenhuma mudança deste plano toca em TX (funcional, ~95%), na lógica de
  OWN/rings de RX (já corrigida), ou nas sequências de calibração PHY
  reverse-engenheiradas — blast radius limitado ao sysfs de diagnóstico e ao
  log de debug.
- Ciclo de teste: editar `mts.c`/`mts.h` → `sudo scripts/build_mts_module.sh`
  → `./scripts/deploy_mts.sh push` → `./scripts/deploy_mts.sh test`. Fases A e
  B devem ser testadas juntas numa única recompilação/reload.
- Topologia de rede (fixada em `AGENTS.md`): WiFi (`192.168.6.128`) só para
  telnet/administração; `eth0` sob teste é `192.168.0.2`, host `192.168.0.1`
  via `enp60s0` — não confundir durante os testes da Fase C.
- Sem necessidade de aviso/espera de "pronto" do usuário para este plano —
  não envolve `send_payload_loop.py` nem a Regra de Ouro da Injeção, é debug
  de um kernel Linux já inicializado e acessível via telnet.

### Arquivos principais

- `drivers_mts/mts.c` — `mts_rx_clean` (1118-1175), `mts_regs_show`
  (1328-1440), `mts_link_check` (998-1044), `mts_mac_enable` (972-993),
  `mts_mdio_read` (156-172)
- `drivers_mts/mts.h` — `MTS_LINK_STATUS`/`MTS_LINK_DUPLEX_FULL` (118-124),
  `MTS_MAC_EN1`/`MTS_MAC_EN2` (42-43), `struct mts_priv` (128+)
- `scripts/build_mts_module.sh`, `scripts/deploy_mts.sh`
- `AGENTS.md` (regra de topologia de rede)
