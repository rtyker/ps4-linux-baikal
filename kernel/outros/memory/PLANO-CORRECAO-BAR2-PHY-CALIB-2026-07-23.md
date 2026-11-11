---
name: plano-correcao-bar2-phy-calib
description: Plano de correção pós-teste ao vivo — crash na calibração PHY (stack overflow) e BAR2/glue
metadata:
  type: project
---

# 🔧 PLANO DE CORREÇÃO — BAR2/Glue e Calibração PHY (mts.ko)

**Data:** 2026-07-23
**Gatilho:** Teste ao vivo — módulo carregado, calibração rodou, **eth0 sumiu** (crash)
**Status:** Causa raiz do crash IDENTIFICADA por revisão estática — pronto para correção

---

## 0. Resumo do que o teste ao vivo revelou

| Achado | Detalhe |
|---|---|
| GBE (00:14.1) só tem BAR0 | `pci_resource_len(pdev, 2)` do próprio GBE é 0 — não existe BAR2 nesse device |
| glue real está em 00:14.4 @ 0xc8800000 | Já corrigido no código atual: `mp->regs_glue = ioremap(0xc8800000, 0x2000)` (linhas 1292-1293) — **essa parte funciona e já foi validada ao vivo** (valores reais lidos: `0x6c=0x331250b5`, `0x5c=0x33125095`) |
| Condição `(p0 & 0x80800000) == 0x80800000` falha | Com os valores reais, o bloco grande de calibração MDIO (linhas 462-571) **nunca executa** — inócuo, não é a causa do crash |
| Módulo crashou, eth0 sumiu | Ocorreu durante/após a calibração — precisa de causa raiz concreta (não é só "código pós-if bugado" em abstrato, ver seção 1) |

**Conclusão preliminar:** a premissa "BAR2 fix já funciona" está correta e não precisa de mais trabalho. O crash está em outro lugar, identificado abaixo.

---

## 1. 🔴 CAUSA RAIZ DO CRASH — Stack Buffer Overflow confirmado (PRIORIDADE 0)

**Localização:** `mts_phy_calibration()`, linhas 706-773 (bloco "Calibration loop via 0x1bc-0x1d4")

```c
u32 calib_tbl[32];   // índices válidos: 0..31 (128 bytes)
u32 calib_msk[32];

ci = 0x22;                                  // 34 — JÁ fora dos limites válidos

calib_tbl[ci + 2] = 0x6721;                 // [36]  ❌ OOB
calib_msk[ci + 2] = 0xffff;                 // [36]  ❌ OOB

calib_tbl[ci | 9] = 0x003;                  // [43]  ❌ OOB
calib_msk[ci | 9] = 0xffff;                 // [43]  ❌ OOB

calib_tbl[ci | 8] = 0x80004000;             // [42]  ❌ OOB
calib_tbl[ci | 8 | 1] = 0x00000034;         // [43]  ❌ OOB

ci = ((ci | 8) + 0xe) | 2;                  // 58
calib_tbl[ci] = 0x18000000;                 // [58]  ❌ OOB
calib_tbl[ci + 1] = 0x40;                   // [59]  ❌ OOB
calib_msk[ci] = 0xffffffff;                 // [58]  ❌ OOB
calib_msk[ci + 1] = 0xffff;                 // [59]  ❌ OOB

calib_tbl[ci + 6] = mac_low;                // [64]  ❌ OOB
calib_tbl[ci + 7] = mac_high >> 16;         // [65]  ❌ OOB
```

**Análise:** todo índice usado (36, 42, 43, 58, 59, 64, 65) excede o tamanho do array (32 posições). A escrita mais distante (`calib_tbl[65]`) fica **132 bytes além do fim** de um buffer de 128 bytes na stack do kernel — sobrescreve variáveis vizinhas na função (possivelmente `mp`, `field`, `val16`, ponteiros salvos) e, dependendo do layout gerado pelo compilador, pode corromper o canário de stack (`CONFIG_STACKPROTECTOR`) ou o endereço de retorno.

**Por que isso explica exatamente "eth0 sumiu":**
- A corrupção acontece **dentro** de `mts_phy_calibration()`, chamada a partir de `mts_mac_enable()`, chamada a partir de `mts_probe()` **antes** de `register_netdev()` ainda rodar mais adiante no fluxo (stage 4).
- Se o stack protector do kernel detectar a corrupção ao retornar da função, gera **panic imediato** (`stack-protector: kernel stack corrupted`) — pode até não aparecer no dmesg antes do reset/watchdog, o que bate com "sumiu sem mensagem clara".
- Se não houver canário nessa função (ou a corrupção não atingir o canário), variáveis locais adjacentes corrompidas podem fazer o resto do `mts_probe()` seguir com estado inválido — `register_netdev()` falha silenciosamente ou o netdev é criado e depois cai.

**Causa raiz da causa raiz:** o comentário no código (`/* offset fixo, como decompilado */`) revela o erro de modelagem: `ci = 0x22` no binário Orbis é quase certamente um **offset em bytes dentro do softc gigante** (a struct real tem milhares de bytes, offsets documentados em `consolidado/RE_KERNEL_GBE_ATTACH.md` chegam a `0x3210`). Transplantar esse número diretamente como **índice de um array `u32[32]` local de 128 bytes** nunca poderia caber — é uma extrapolação inválida da RE, não uma tradução fiel.

### 1.1 Correção imediata (obrigatória antes de qualquer novo teste ao vivo)

**Opção A — Recomendada agora: desativar o bloco por completo**

Envolver as linhas 701-771 (todo o "Calibration loop via 0x1bc-0x1d4", incluindo a construção de `calib_tbl`/`calib_msk` e o loop de `mts_write(mp, 0x1bc/0x1c0/0x1c4/0x1c8, ...)`) atrás de um novo module param, default OFF:

```c
static bool enable_phy_calib_table = false;
module_param(enable_phy_calib_table, bool, 0644);
MODULE_PARM_DESC(enable_phy_calib_table,
	"Habilita loop de calibracao via tabela indexada 0x1bc-0x1d4 (EXPERIMENTAL, default false — bug de stack overflow corrigido mas logica da tabela nao verificada)");

...

if (enable_phy_calib_table) {
	u32 calib_tbl[32];
	...
}
```

Isso por si só já resolve o crash (o bloco simplesmente não roda), mas a lógica de dentro **continua incorreta** e não deve ser reativada sem a Opção B.

**Opção B — Antes de reativar: RE correta da tabela**

A tabela sendo construída não é um array `u32[32]` — precisa ser reanalisada a partir de `consolidado/decompiled_dc5a0ba0_gbe_phy_calib.txt` (linhas ~382-506, a parte ainda não lida completamente nesta sessão) com foco em:
1. Qual é o tamanho real da estrutura (softc + offset, não array local)?
2. `0x1bc`/`0x1c0`/`0x1c4`/`0x1c8`/`0x1d0` formam um mecanismo de **registrador indexado** (escreve índice em 0x1c0, dado em 0x1bc, "commit" em 0x1c4, espera bit de pronto em 0x1d0) — isso é um padrão real de hardware (tabela de coeficientes de calibração acessada indiretamente), mas o **conteúdo** de cada entrada precisa ser extraído registro-a-registro do binário, não reconstruído por adivinhação de offsets.
3. Só depois disso vale reimplementar com um buffer do tamanho certo (provavelmente `loop_count` entradas reais, ~0x42 = 66, não 32).

**Não fazer as duas coisas ao mesmo tempo** — a Opção A desbloqueia testar o resto do driver agora; a Opção B é trabalho de RE separado, sem pressa de reimplementar às cegas de novo.

---

## 2. Restante do "código que sempre roda" (linhas 574-700, fora da tabela)

Depois de isolar o bloco da tabela (seção 1), sobra um trecho grande de writes diretos que **nunca foi validado ao vivo individualmente**:

```
BAR0[0x1e]/page ops (sequências 1-7 via MDIO page 0x1f/0x11/0x12/0x10)
BAR0[0x7c] = 25000000        (já confirmado [MEDIDO] como clock — OK, redundante seguro)
BAR0[0x04] = link_save & 0x7fffcfff     ⚠️ escreve no registrador de STATUS de link
BAR0[0x78] &= ~1                         ⚠️ nunca medido
MDIO 0x33001e read-modify-write          ⚠️ nunca medido
Page 0 read-modify-write (| 0x1200)      ⚠️ nunca medido
BAR0[0x14]/[0x18] = MAC address          ✅ ok, mesmo endereço já usado por mts_get_mac_address
BAR0[0x0c] &= ~0x80                      ⚠️ nunca medido
BAR0[0x74] = 0x2277                      ✅ já confirmado [MEDIDO]/[RE], redundante seguro
BAR0[0x08] |= 0x7597c00                  ⚠️ nunca medido, altera MUITOS bits de uma vez
BAR0[0x1d4] = 1                          ⚠️ nunca medido
BAR0[0x10] = (val & 0xffffff6e) | 0x81   ⚠️ nunca medido
BAR0[0x30] = 0x10100                     ✅ já confirmado [MEDIDO]/[RE], redundante seguro
```

**Risco:** `BAR0[0x04]` é exatamente o `MTS_LINK_STATUS` que `mts_link_check()` lê para decidir carrier — escrever nele antes de entender seu formato completo pode mascarar bits que o hardware usa para outra coisa (não necessariamente só leitura). `BAR0[0x08] |= 0x7597c00` mexe em 12+ bits de uma vez sem registro do que cada um faz.

### 2.1 Ação recomendada

Não cortar esse trecho (ele é provavelmente necessário — inclui o que o Orbis realmente faz sempre, fora do `if`), mas:
1. Adicionar `dev_info()` **antes e depois** de cada escrita não confirmada (`0x78`, `0x33001e`, page 0, `0x0c`, `0x08`, `0x1d4`, `0x10`) — nesse formato: `dev_info(dev, "pre  0x78=0x%08x\n", mts_read(mp,0x78)); mts_clear(...); dev_info(dev, "post 0x78=0x%08x\n", mts_read(mp,0x78));`
2. Isso transforma o próximo teste ao vivo em uma **coleta de dados**, não um chute — depois de rodar uma vez (com a tabela da seção 1 desativada), teremos o efeito real de cada escrita no dmesg, sem precisar reverter nada.
3. Manter esse bloco condicionado a `enable_phy_calib` (já existe) — se o link não vier, dá pra desabilitar tudo com `enable_phy_calib=0` sem rmmod/rebuild.

---

## 3. BAR2/Glue — limpeza (não bloqueante, mas fazer junto)

O mapeamento em si **já funciona** — não mexer na lógica. Só dívida técnica:

1. **Renomear macros:** `MTS_BAR2_CALIB_0..4` (mts.h:88-92) sugerem "BAR2 do GBE", mas na verdade é o glue em 00:14.4. Renomear para `MTS_GLUE_CALIB_0..4` e atualizar os 5 usos em `mts.c` (linhas 451-455). Puramente cosmético, mas evita confusão futura (a mesma confusão que causou o desvio original).

2. **Conflito de posse do MMIO:** `ioremap(0xc8800000, 0x2000)` é feito **sem** `request_mem_region()`. Se `drivers/ps4/ps4-bpcie*.c` (o driver do glue já existente no kernel) também mapear essa região, não há erro imediato (ioremap não exige exclusividade), mas há risco de leitura durante uma escrita concorrente do outro driver. Verificar:
   ```bash
   grep -rn "0xc8800000\|BPCIE.*GLUE\|glue.*ioremap" /mnt/hdauxiliar/temp/kernel_build_7.0/drivers/ps4/
   ```
   Se o glue já for mapeado por outro driver com um símbolo exportado (ex: `bpcie_glue_base()`), preferir reusar esse ponteiro em vez de um segundo `ioremap` independente. Se não houver exportação, manter como está (funciona, só não é o ideal) — não é bloqueador para os próximos testes.

---

## 4. MDIO Clause 45 vs Clause 22 — só depois de eliminar a causa do crash

A hipótese é legítima (o padrão de "page select via reg 0x1f + shadow regs 0x10-0x12" nas sequências de page ops lembra mais um mecanismo de **página estilo Broadcom** que normalmente roda sobre **Clause 22**, não Clause 45), mas:

- **Não investigar agora.** Ela é ortogonal ao crash (que é 100% o stack overflow da seção 1) e ortogonal à condição `(p0 & 0x80800000)` (que só decide se o bloco *grande* de calibração roda — o bloco de page ops de "sempre roda" já usa Clause 45 hoje independente disso).
- **Quando investigar:** só depois que os testes da seção 2 (writes instrumentados) rodarem ao vivo sem crash e ainda assim carrier continuar DOWN. Nesse ponto, se os `dev_info()` mostrarem que as escritas MDIO via `mts_mdio_write()` (Clause 45: fase ADDR + fase READ/WRITE) não estão de fato mudando nada no PHY (ex: leituras subsequentes sempre retornam o residual/0xffff, como já visto antes em `mts_mdio_probe()`), aí sim vale testar um caminho Clause 22 alternativo — que seria uma função nova `mts_mdio_write_c22()` usando um formato de opcode diferente no mesmo registrador BAR0+0x00 (formato depende de RE adicional, não temos essa parte decompilada ainda).
- Manter como item registrado, não como próximo passo imediato.

---

## 5. Estratégia de Teste Incremental

### 5.1 Novos module params (granularidade para não precisar rebuild a cada teste)

```c
static bool enable_phy_calib = true;          // já existe — liga/desliga tudo
static bool enable_phy_calib_table = false;   // NOVO — bloco da tabela 0x1bc-0x1d4 (seção 1), default OFF
```

### 5.2 Sequência de testes ao vivo (cada um é 1 power cycle)

| # | Config | Objetivo | Critério de sucesso |
|---|--------|----------|---------------------|
| 1 | `enable_phy_calib=1 enable_phy_calib_table=0` | Confirmar que o crash sumiu (é só a tabela) | `eth0` continua presente após `insmod`, `dmesg` não mostra oops/panic |
| 2 | Igual ao #1, com `dev_info()` da seção 2.1 adicionados | Coletar efeito real de cada escrita não confirmada | dmesg mostra pre/post de `0x78`, `0x08`, `0x0c`, `0x1d4`, `0x10`, `0x33001e`, page 0 |
| 3 | Igual ao #1/#2 | Checar carrier | `cat /sys/class/net/eth0/carrier` — mesmo que ainda dê 0, não é falha do teste, é dado |
| 4 | (condicional ao resultado do #3) | Se carrier=1: sucesso, driver funcional sem a tabela | Ethernet operacional |
| 5 | (condicional) | Se carrier=0: decidir entre RE da tabela (seção 1, Opção B) ou investigar Clause 22 (seção 4) | — |

**Nunca reativar `enable_phy_calib_table=1` sem antes fazer a Opção B da seção 1.**

---

## 6. Checklist de Implementação

- [ ] Envolver bloco `calib_tbl`/`calib_msk`/loop 0x1bc-0x1d4 (linhas 701-771) em `if (enable_phy_calib_table)`
- [ ] Adicionar module_param `enable_phy_calib_table` (default `false`) com `MODULE_PARM_DESC` explicando o motivo
- [ ] Adicionar `dev_info()` pre/post nas escritas não confirmadas da seção 2 (0x78, 0x08, 0x0c, 0x1d4, 0x10, 0x33001e, page 0)
- [ ] (Opcional, não bloqueante) Renomear `MTS_BAR2_CALIB_*` → `MTS_GLUE_CALIB_*`
- [ ] (Opcional, não bloqueante) Checar se `drivers/ps4/ps4-bpcie*.c` já expõe o glue mapeado
- [ ] Recompilar com `scripts/build_mts_module.sh`
- [ ] Atualizar `memory/tentativas-frustradas-mts-carrier.md` com o resultado do crash + a causa raiz (stack overflow), antes do próximo teste ao vivo — regra do CLAUDE.md item 2
- [ ] Teste ao vivo #1 da tabela da seção 5.2 **só após autorização explícita do usuário** ("pronto")

---

## 7. Resumo Executivo

| Pergunta do usuário | Resposta |
|---|---|
| BAR2 fix funciona? | ✅ Sim, já implementado e validado ao vivo — nenhuma mudança necessária, só renomear macros por clareza |
| Quais operações são necessárias para o link? | Ainda não sabemos — a seção 2 vira instrumentação, não suposição, no próximo teste |
| Sequência de page ops é segura com MDIO retornando 0? | Sim, tecnicamente segura (não trava, só não faz efeito útil se PHY não responder) — não é a causa do crash |
| Tabela 0x1bc-0x1d4 causa crash? | ✅ **Confirmado** — stack buffer overflow real (índices até 65 num array de 32), não é heurística, é bug de código verificável estaticamente |
| Implementar a tabela corretamente ou pular? | **Pular agora** (module param OFF), implementar depois com RE dedicada (Opção B, seção 1.1) — não misturar as duas tarefas |
| Testar Clause 22? | Só depois do teste #3 da seção 5.2, se carrier continuar DOWN sem a tabela |
| Teste incremental? | Sim — plano de 5 passos na seção 5, cada um consumindo 1 power cycle |

---

## Referências

- [revisao-implementacao-phy-calib-2026-07-23.md](revisao-implementacao-phy-calib-2026-07-23.md) — revisão anterior (pré-teste ao vivo, código na versão sem o bloco da tabela ainda)
- [PLANO-REVISAO-PHY-CARRIER-2026-07-23.md](PLANO-REVISAO-PHY-CARRIER-2026-07-23.md) — plano original
- `consolidado/decompiled_dc5a0ba0_gbe_phy_calib.txt` — fonte da tradução, releitura necessária para a Opção B da seção 1
- `drivers_mts/mts.c:701-773` — bloco com o bug confirmado
