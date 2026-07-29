# Plano: Investigar `MTS_MAC_EN2` (0x38) travado em 0x00000000

## Contexto

Testes ao vivo de hoje (Fase A/B do plano de duplex/PHY, ambos confirmados
implementados e funcionando corretamente) mostraram dois achados que ficaram
em aberto:

1. **Fase A (log throttling): resolvido.** Contador persistente
   `mp->rx_debug_logs` funciona — log para depois de 10 ocorrências, sem spam.
2. **Fase B (leitura PHY Clause 45 ao vivo): implementada, mas inconclusiva.**
   Todos os registradores padrão (PMA/PMD Control1/Status1/ID1/ID2, AN Status,
   1000BASE-T AN Status) retornam `0x0000` com `ret=0` (sem timeout) — ou seja,
   a transação MDIO completa, mas não há dado real. Isso não confirma nem
   refuta o duplex reportado pelo MAC (`0x04` = "Half duplex"); só mostra que
   o PHY não responde com sinal algum nesses registradores via esse
   endereçamento devad/reg, tanto durante a calibração inicial quanto **depois**
   do "Link change" já ter aparecido.
3. **Achado reproduzível (2 sessões seguidas hoje):** `MTS_MAC_EN2` (offset
   `0x38`) lê `0x00000000` tanto imediatamente após o probe quanto minutos
   depois (via sysfs `mts_regs`, antes e depois de tentativa de ping). Um
   comentário no código (`mts.c:983-985`, presente desde o commit inicial
   `d49f085`, portanto **anterior a todo o histórico git deste repositório** —
   não é uma regressão de nenhum commit rastreável aqui) afirma que sessões
   anteriores (não documentadas neste repo) viram `0x38` ler `0x08` após o
   enable. Não há como confirmar em que condições exatas essa observação foi
   feita.

`MTS_CNT_PKTS` continua em 0 e o ping direto na subnet correta
(`192.168.0.1` ↔ `192.168.0.2`, cabo CAT6 direto, ambas as pontas gigabit)
continua em 100% de perda.

**Hipótese unificadora a testar:** os três achados (PHY Clause 45 sempre
zero, `MTS_MAC_EN2` sempre zero, duplex "Half" a 1000Mbps) podem não ser três
bugs independentes, mas **sintomas do mesmo problema de fundo**: o PHY nunca
completa de fato o power-up/negociação física, e todos os registradores que
dependem disso (MAC enable readback, registradores PHY MDIO, decodificação de
duplex) ficam presos em um estado "degradado" coerente entre si. Este plano
testa essa hipótese antes de tratar `MTS_MAC_EN2` como um problema à parte.

---

## Fase 1 — Confirmar o momento exato em que `0x38` aparece zerado (sem mexer em código)

Antes de qualquer mudança, reler o dmesg de hoje (já capturado, sem necessidade
de novo teste ao vivo) procurando a linha específica:

```
dmesg | grep "MAC enable:"
```

Essa linha (`mts.c:987`) já loga `0x34`/`0x38`/`0x50`/`0x70` **imediatamente**
após o `mts_set()` que tenta habilitar o MAC, **antes** de
`mts_phy_calibration()` rodar (chamada na linha seguinte, `mts.c:991`). Se
essa linha já mostrar `0x38=0x00000000` no boot de hoje, o registrador nunca
reteve o bit desde o início — não é a calibração que está limpando depois.
Se mostrar `0x38=0x00000008` (ou qualquer valor não-zero) nessa linha mas a
leitura via sysfs minutos depois mostrar zero, então algo **entre** o enable e
a leitura posterior (mais provavelmente dentro de `mts_phy_calibration()`,
`mts.c:551-968`) está zerando o bit.

**Critério de sucesso:** saber, sem escrever uma linha de código, se o "drop"
acontece antes ou depois da calibração.

---

## Fase 2 — Bisecção com uma única linha de log adicional

**Arquivo:** `drivers_mts/mts.c:972-993` (`mts_mac_enable`).

Se a Fase 1 for inconclusiva (ex.: log de hoje não foi capturado/perdido no
scroll do dmesg), adicionar **um único** log extra logo depois da chamada
`mts_phy_calibration(mp);` (linha 991), relendo `0x34`/`0x38`/`0x50`/`0x70`
mais uma vez:

```c
mts_phy_calibration(mp);

dev_info(&mp->pdev->dev,
         "MAC enable (pos-calib): 0x34=0x%08x 0x38=0x%08x 0x50=0x%08x 0x70=0x%08x\n",
         mts_read(mp, MTS_MAC_EN1), mts_read(mp, MTS_MAC_EN2),
         mts_read(mp, 0x50), mts_read(mp, 0x70));
```

Nenhuma sequência de calibração reverse-engenheirada é alterada — só uma
leitura adicional, risco trivial. Confirmado por grep que nenhum ponto dentro
de `mts_phy_calibration()` escreve diretamente em `0x38` (só existe a escrita
via `mts_set()` antes da calibração) — então, se o valor cair para zero depois
da calibração, não é uma escrita direta e sim efeito colateral de algum outro
registrador correlacionado (ex. reset implícito, ou o próprio hardware
zerando o bit quando detecta que o link/PHY não está de fato pronto).

**Critério de sucesso:** duas leituras lado a lado (antes/depois da
calibração) no mesmo boot, confirmando ou refutando se a calibração é o
ponto exato da mudança.

---

## Fase 3 — Teste A/B com `force_mac_reset`

Já existe o module param `force_mac_reset` (default `false`,
`mts.c:68-70`), que quando `true` chama `mts_mac_stop()` (limpa EN1/EN2) antes
do fluxo normal de `stage>=2`. Rodar dois loads consecutivos (mesma sessão de
boot, sem power cycle):

1. `insmod mts.ko stage=4` (padrão, como já testado).
2. `rmmod mts; insmod mts.ko stage=4 force_mac_reset=1`.

Comparar a saída de `mts_regs` (via `deploy_mts.sh test` ou telnet direto)
entre os dois — se os registradores `0x50`/`0x70` (que o comentário do código
aponta como onde "o estado aparece" quando `0x38` não retém) diferirem
mensuravelmente entre os dois modos, isso dá uma pista de qual registrador é
a fonte de verdade real do estado de enable, independente de `0x38`.

**Critério de sucesso:** saber se `0x50`/`0x70` mudam de valor conforme o
MAC é de fato (re)habilitado, dando um substituto confiável para `0x38` como
indicador de "MAC realmente ligado".

---

## Fase 4 — Testar Clause 22 (MII) diretamente no registrador BMCR

Como a Fase B (Clause 45) não deu sinal algum do PHY, e já existe fallback
Clause 22 implementado (`mts_mdio_c22_read`/`write`, `mts.c:236-271`, hoje só
usado no diagnóstico `mts_mdio_probe` que reportou timeout `-110`), vale uma
tentativa focada e barata: ler o registrador padrão **BMCR** (Clause 22,
`reg=0x00`) — bit 11 = power-down, bit 15 = reset, bit 8 = duplex, bits
13+6 = velocidade. Isso é universal em qualquer PHY Clause 22/MII e é o
registrador mais provável de mostrar se o PHY genuinamente saiu do
power-down, complementando (não substituindo) a Fase B.

Adicionar ao sysfs `mts_regs` (mesma função `mts_regs_show`,
`mts.c:1328-1440`) uma leitura de `mts_mdio_c22_read(mp, phy_addr, 0x00,
&val)` — usar o mesmo `phy_addr` já usado em `mts_mdio_probe`/testes
anteriores (checar valor exato usado nas chamadas C22 já existentes no
código antes de escrever, para não introduzir um endereço diferente sem
justificativa).

**Critério de sucesso:** ter uma leitura de BMCR ao vivo pós-link, com
`ret=0` idealmente não-zero, complementando a Fase B.

---

## Fase 5 — Decisão

- **Se Fase 1/2 mostrar que `0x38` já nasce zero (antes de qualquer
  calibração):** tratar como comportamento provavelmente normal/no-retain
  (like `0x34`), não como bug. Redirecionar 100% da atenção para a hipótese
  unificadora (PHY nunca sai de power-down) — Fase 4 (BMCR) vira a
  investigação principal.
- **Se Fase 2 mostrar que a calibração especificamente zera `0x38`:** ainda
  assim, dado que nenhuma escrita direta a `0x38` existe dentro da
  calibração, ISSO seria uma pista forte de que o próprio hardware está
  revertendo o enable como reação a alguma condição de PHY malsucedida —
  reforça a hipótese unificadora igualmente, mas aponta para investigar
  exatamente qual sub-sequência da calibração (bisecção dentro de
  `mts_phy_calibration`, fora de escopo deste plano) dispara isso.
- Em ambos os casos, a Fase 4 (BMCR Clause 22) é o próximo diagnóstico mais
  barato e informativo — se ele também vier zero/timeout, a conclusão prática
  é que este PHY realmente não está saindo do estado poweredown com a
  sequência de wakeup atual, e o próximo projeto (fora de escopo, maior RE)
  seria revisar a sequência de wakeup do PHY (`mts.c` região de
  "PHY wakeup: tentando acordar PHY via Glue + MDIO") em busca de um passo
  faltante.

---

## Riscos

- Fases 1 e 3 são só leitura/teste com module param já existente — risco
  zero de regressão.
- Fase 2 adiciona uma única linha de log — risco trivial, não toca nenhuma
  sequência RE'd.
- Fase 4 é só leitura MDIO adicional no sysfs, mesmo padrão de risco já
  validado na Fase B (sem escritas novas).
- Nenhuma fase mexe em TX (funcional) ou na lógica de anéis RX (já corrigida).

### Arquivos principais

- `drivers_mts/mts.c` — `mts_mac_enable` (972-993), `mts_phy_calibration`
  (551-968), `mts_mdio_c22_read`/`write` (236-271), `mts_mdio_probe` (282+),
  `mts_regs_show` (1328-1440)
- `drivers_mts/mts.h` — `MTS_MAC_EN1`/`MTS_MAC_EN2` (42-43)
- `scripts/build_mts_module.sh`, `scripts/deploy_mts.sh`
