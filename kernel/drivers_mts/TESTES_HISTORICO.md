# Testes ao vivo do `mts.ko` — histórico consolidado

Registro dos testes de hardware feitos entre 2026-07-22 e 2026-07-30, com o que
**continua valendo** e o que foi **refutado depois**. Substitui os relatórios de
sessão que ficavam soltos em `../outros/docs/relatorios/`
(`PHY_DEBUG_SESSION_20260724.md`, `TESTE_RX_OWN_INVERSION_RESULTADO.md`,
`TESTE_TAIL_POINTER_RESULTADO.md`, `TESTE_TELNET_EH0_SUBNET_2026-07-23.md`,
`TESTE_MAC_EN2_BMCR_RESULTADO_2026-07-23.md`, `RESULTADO_TESTE3.txt`,
`RESUMO_FINAL_TESTE3.txt`) e o `CHANGES_CLAUSE22_2026-07-23.md`.

> A fonte estruturada (consultável por SQL) continua sendo a tabela `test_history`
> do [`../outros/rea/ps4_hardware_memory.db`](../outros/rea/ps4_hardware_memory.db):
> `SELECT id, timestamp, phase, test_name, status FROM test_history ORDER BY id;`
> Este arquivo dá o contexto e a leitura crítica que o banco não tem.

Ambiente de todos os testes: PS4 Pro Baikal real, kernel
`7.0.8-Strawberry-ThinLTO-Baikal-+`, SSH/telnet por WiFi (`192.168.6.128`).
O `eth0` é sempre testado na subnet **`192.168.0.0/24`** (PS4 `.2`, PC `.1`).

---

## Linha do tempo

| # | Data | Mudança testada | Resultado | Vale até hoje? |
|---|---|---|---|---|
| 1 | 2026-07-22 | `stage=4` completo | `eth0` registrado, MAC real da SPM, DMA alocado, vídeo OK | ✅ sim — ver [`MARCO_HISTORICO_ETH0_MTS_BAIKAL.md`](MARCO_HISTORICO_ETH0_MTS_BAIKAL.md) |
| 2 | 2026-07-23 | diagnóstico Clause 45 × Clause 22 | C45 `ret=0 val=0x0000`; C22 `ret=-110` | ⚠️ parcial — a leitura "PHY powered-down" é a correta; "C22 não suportado" foi **refutado** depois |
| 3 | 2026-07-23 | tail pointer TX como endereço | 6 drops, TX não sobe | ❌ refutado |
| 4 | 2026-07-23 | tail pointer TX como **índice** | **TX resolvido** | ✅ sim |
| 5 | 2026-07-23 | RX init com `OWN=1` | RX "conta" 22 M pacotes/34 GB → loop de lixo | ✅ a inversão é real; o loop foi corrigido depois |
| 6 | 2026-07-23 | primeiro teste de `eth0` na subnet certa | 100% perda, mas teste **válido** pela 1ª vez | ✅ sim |
| 7 | 2026-07-23 | `0x38`/0x34 retêm o enable? | **nunca** retêm; `0x50` é dinâmico | ✅ sim |
| 8 | 2026-07-24 | clock `0x10a030` + `hold_val=0x10` + sem `0x200=0` | MDIO C45 passa a responder; link 1000 half aparece | ✅ sim (mas insuficiente) |
| 9 | 2026-07-25 | RMU fase 1/2, loopback, Clause 22 | DMA completo, PHY mudo, "PHY ID Marvell" | ❌ ID refutado (dado residual) |
| 10 | 2026-07-30 | `irq_mask=0x7d` + MSI desmascarado | `irq_count=0`, `NO-CARRIER` | ✅ refutação final de software |

---

## Detalhe por sessão

### 1. Bring-up de `eth0` — 2026-07-22

`stage=4` com o driver já estável: `eth0` registrado, MAC `2c:cc:44:3f:69:5f` lido
da SPM, anéis TX `0x010dd000` / RX `0x010de000`, `IMR=0`, zero panic. Detalhes e
dmesg em [`MARCO_HISTORICO_ETH0_MTS_BAIKAL.md`](MARCO_HISTORICO_ETH0_MTS_BAIKAL.md).

### 2. Diagnóstico Clause 45 × Clause 22 — 2026-07-23

Primeira execução do `mts_mdio_probe()` com as duas vias:

```
Clause 45: ret=0 val=0x0000
Clause 22: ret=-110 val=0xffff
```

- **Duravél:** o PHY responde "sem timeout" em Clause 45, mas **devolve zero em
  todos os registradores** — padrão de PHY sem alimentação/clock, não de protocolo errado.
- **Refutado:** a conclusão da época de que "Clause 22 não é suportado". Depois se
  descobriu que o timeout era **bug de polaridade** em `mts_mdio_wait_write()`
  (esperava o bit 15 zerar; o correto é esperar setar). Corrigido em 2026-07-29/30.

### 3–4. Tail pointer TX — 2026-07-23

`mts_start_xmit()` não avisava o hardware do novo descritor. Duas variantes:

| Variante | Resultado |
|---|---|
| `0x3c = tx_ring_dma + idx*16` (endereço) | 6 drops, TX não sobe |
| `0x3c = tx_idx` (índice 0–255) | **TX resolvido** |

O mesmo vale para RX (`0x40 = rx_idx`). Isso virou código em `mts_tx_reclaim()` /
`mts_rx_clean()`.

### 5. Inversão de `OWN` no RX — 2026-07-23

RX inicializado com `OWN=0` não processava nada. Com `OWN=1` na inicialização
("buffer vazio, hardware pode escrever") a interface passou a contar pacotes —
**22.372.508 pacotes / 34 GB** em segundos, números impossíveis para GbE.

- **Duravél:** a semântica é **invertida em relação ao TX**. TX: `OWN=1` = "livre
  para o software". RX: `OWN=1` = "livre para o hardware receber".
- **Causa do número absurdo:** `mts_rx_clean()` não parava — o loop relia
  descritores que nunca eram devolvidos. Corrigido com `if (ctl & MTS_DESC_OWN) break;`
  e o throttle de log (`rx_debug_logs`, 1 a cada 1000).

### 6. Primeiro teste de `eth0` na subnet correta — 2026-07-23

Descoberta metodológica importante: **todos os pings anteriores tinham sido feitos
para `192.168.6.x` e respondiam pelo `wlan0`** — não validavam nada. Com
`192.168.0.1 ↔ 192.168.0.2` o resultado foi honesto: 100% de perda.

Também confirmado nessa sessão: `mts_regs` no sysfs funcionando, RX
logicamente coerente, e o `0x38` **não** retendo o bit de enable.

### 7. `MAC_EN2` (0x38) e BMCR — 2026-07-23

- `0x38` nasce `0` e **nunca retém** o bit após a escrita, antes ou depois da
  calibração. Idem `0x34`. Não é bug nem efeito da calibração — é o
  comportamento do silício (write-only / efeito colateral).
- `0x50` é o **único** registrador que muda de forma dinâmica e correlacionada
  com a calibração (`0xa4` → `0x00` → `0x42` conforme o momento). Significado
  ainda não determinado.
- Clause 22 em `phy_addr=0` só dava timeout limpo — sem crash, sem dado.

### 8. Sessão de debug do PHY — 2026-07-24

Quatro variantes de hold/pulse/calibração. A que funcionou parcialmente:

```
clock 0x10a030 = (reg & 0xfffffe07) | 0xd8   ->  0x16c9 vira 0x16d9 (bit 4), persiste entre reloads
hold_val = 0x10 (bit 4)                       ->  Clause 45 passa a responder (ret=0)
remover a escrita 0x200 = 0                   ->  MAC enable para de morrer
```

Com isso: `Link change: 1000 Mbps Half duplex`, 20 pacotes TX enfileirados,
registradores do MAC vivos — **mas `MTS_CNT_PKTS=0`, RX nunca recebe e o PHY
continua sem tráfego real**.

Também foi reescrita a rotina de stop seguindo `dc5a3060`:

```
0x54 = 0x7ffffa  ->  0x34 = 2 + poll bit 1  ->  0x38 = 2 + poll bit 1
-> drena TX/RX  ->  0x1c8 &= ~0x440
```

> O `hold_val=0x10` (bit 4, como a GBE do Orbis) é o padrão correto para testes de
> MDIO, mas **não liga o link** — o default do módulo continua `0x1`.

### 9. RMU, loopback e o falso "PHY ID Marvell" — 2026-07-25

- Quadro RMU de 34 bytes (magic `0xfa42`, sub-header `0x9807`): o DMA TX aceita e
  devolve `OWN`, mas nada muda do lado do PHY.
- Loopback interno do MAC: sem retorno de RX.
- A leitura que parecia identificar o PHY (`ID1=0x8881`, `ID2=0x03a2`) foi
  **refutada no mesmo dia** e formalmente em 2026-07-30 (`test_history` id 70):
  era dado residual do barramento MDIO — a transação nunca completava e o bus
  devolvia o último valor latched. **Não existe "PHY Marvell identificado".**

### 10. MSI, IMR e demux — 2026-07-30

Com MSI desmascarado em hardware (`lspci`: `Enable+ Count=1/1`, `Masking=00000000`),
`irq_mask=0x7d` aplicado em `0x54`, e o demux do glue correto para a GBE
(`bpcie_assign_irqs(pdev, 1)`, vetor único): `/proc/interrupts` continuou com
`irq_count=0`, `eth0` `NO-CARRIER`, ping 100% perda (`test_history` id 72).

**Conclusão:** o PHY nunca gera evento — nem link change, nem conclusão de RX.
O MAC/DMA está operacional e "fala sozinho". Isso fecha a linha de investigação
de software; o PHY é ligado pelo firmware/bootloader Sony antes do kernel
(ver [`PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md`](PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md)).

---

## O que continua verdade (resumo)

1. `0x3c`/`0x40` recebem **índice**, não endereço.
2. `OWN` tem semântica invertida entre TX e RX.
3. `0x34`/`0x38` não retêm valor; não interpretar leitura `0` como falha.
4. Clock `0x10a030` com bit 4 setado é pré-requisito para o MDIO responder.
5. `0x200 = 0` mata o MAC enable até o próximo power cycle — nunca escrever.
6. Hold da GBE = `0x180020`, pulse = `0x180074`; `hold_val` usa **bit 4** (`0x10`).
7. Por convenção do projeto, todo teste de `eth0` usa `192.168.0.0/24`.

## O que foi refutado (não repetir)

| Hipótese | Situação |
|---|---|
| "Clause 22 não é suportado pelo PHY" | bug de polaridade nosso, corrigido |
| "PHY é um Marvell identificado por `0x888103a2`" | dado residual de barramento |
| "Varredura de `phy_addr` 0–31 resolve" | as funções Orbis não têm parâmetro de endereço útil |
| "MSI/IMR/demux está mascarando a IRQ" | testado desmascarado, `irq_count=0` |
| "Falta um passo de ICC/SAMU/RMU para ligar o PHY" | RE completa não achou nenhuma chamada |
| "Tail pointer TX é endereço" | é índice |
| "`0x38` deveria ler `0x08`" | não retém, é o normal do silício |
