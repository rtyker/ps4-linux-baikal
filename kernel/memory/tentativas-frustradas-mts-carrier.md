# Tentativas Frustradas — Validação mts.ko eth0

## 2026-07-23 — BTF validation mismatch no módulo novo

**Sintoma:**
```
distilled base BTF type 'long long unsigned int' [5] is not mapped to base BTF id
failed to validate module [mts] BTF: -22
insmod: ERROR: could not insert module ... mts.ko: Invalid parameters
```

**Causa:** O módulo foi compilado com `CONFIG_DEBUG_INFO_BTF=y` (herdado do `.config` do kernel). O BTF gerado pelo `pahole`/`objtool` durante o `make M=... modules` difere do BTF base do kernel rodando (provavelmente `pahole` versão diferente ou rebuild parcial da árvore).

**Tentativas:**
1. ❌ `insmod mts.ko stage=4` → BTF -22
2. ❌ `insmod mts.ko` sem params → BTF -22
3. ❌ `insmod mts.ko stage=4 force_mac_reset=0 enable_carrier=0 enable_rx=0 enable_tx=0 poll_interval_ms=10` → BTF -22
4. ❌ `objcopy --strip-debug mts.ko` + insmod → BTF -22 (`.BTF` não é seção debug)
5. ✅ **Solução Encontrada (Antigravity):** Removendo explicitamente as seções `.BTF` e `.BTF.base` que causam o erro de validação distilada:
   ```bash
   objcopy --remove-section=.BTF --remove-section=.BTF.base mts.ko
   ```
   Como o kernel não obriga que módulos tenham BTF (apenas valida se a seção estiver presente), a remoção dessas seções permite o carregamento limpo.
   
    **Status:** Automatizei isso no `build_mts_module.sh`. O módulo já foi recompilado e está limpo de seções BTF em `drivers_mts/build/mts.ko`, pronto para teste de `insmod`!

---

## Teste 2 — Fase B Carrier (mts.ko BTF-stripped carregado)

**Setup:** `insmod mts.ko stage=4` (OK), `ip link set eth0 up`, `echo 1 > enable_carrier`, `echo 1 > enable_rx`

**Sintoma:**
```
cat /sys/class/net/eth0/carrier → 0 (NO-CARRIER)
operstate → down
dmesg: NENHUMA mensagem "Link UP" ou "Link DOWN"
```

**Causa Raiz (dupla):**
1. ⚠️ **Ordem:** `ip link set eth0 up` foi chamado ANTES de setar `enable_carrier=1` via sysfs → o timer/NAPI nunca foi criado, pois `mts_open()` só inicia o timer se `enable_*` for true no momento do open
2. ⚠️ **Timer não cobre carrier:** mesmo se o timer existisse, `mts_poll_timer()` chama `napi_schedule()` só se `enable_rx || enable_tx` — `enable_carrier` sozinho nunca dispara a poll

**Teste seguinte:** Reconfigurado para setar `enable_carrier=1 enable_rx=1` ANTES de `ip link set eth0 up`. Log mostra `open (stage=4) carrier=1 rx=1 tx=0` — timer/NAPI criados. **Ainda NO-CARRIER.** Nenhuma mensagem "Link UP" apareceu.

**Leitura direta do registrador BAR0+0x04 via `/dev/mem`:**
```
0x00000b18
```
Decodificação:
- bit0 = 0 → **link DOWN** (hardware reporta sem link)
- bits[3:2] = 2 → speed 1000M
- bit6 = 0 → half duplex

**Interpretação:** O PHY não está detectando o link físico mesmo com cabo conectado. PHY provavelmente precisa de inicialização/calibração extra (ver função `dc5a0ba0` do Orbis que escreve nos registradores `0x140-0x200` e faz calibração de PHY).

## Teste 3 — Fase B com ordem correta + enable_tx (01-07-2026)

**Setup:** `echo 1 > enable_carrier` + `enable_rx` + `enable_tx` ANTES de `ip link set eth0 up`

**Resultado:** `open (stage=4) carrier=1 rx=1 tx=1` ✅. Timer/NAPI criados.

**Carrier:** Ainda `0` (NO-CARRIER). Registrador 0x04 = `0x00000b18` (bit0=0, link DOWN).

**BUG DESCOBERTO — Nenhuma mensagem "Link UP/DOWN" aparece:**
```c
mts_open():  mp->link_up = false;   // estado inicial
mts_link_check():  up = val & 1;    // = 0 (link down)
if (up != mp->link_up) → false != false = false → NUNCA EXECUTA
```
O estado inicial (`link_up = false` coincide com o valor lido do registrador (bit0=0). A primeira leitura nunca detecta "mudança" porque ambos são `false`. **SOLUÇÃO:** inicializar `mp->link_up = true` em `mts_open()`, forçando a primeira leitura a sempre gerar um evento de "mudança".

**Ação necessária:** Corrigir `mts_open()` e recompilar.

---

## Teste 4 — PHY Calibration (dc5a0ba0) implementada, crash ao vivo (2026-07-23)

**Setup:** Implementada tradução de `fcn.ffffffffdc5a0ba0` (calibração PHY) em `mts_phy_calibration()`, incluindo mapeamento do glue (bpcie @ 0xc8800000, 00:14.4 — não é BAR2 do GBE, que só tem BAR0).

**Resultado positivo:** Mapeamento do glue funciona — valores reais lidos ao vivo (`0x6c=0x331250b5`, `0x5c=0x33125095`, etc.). Confirma que `ioremap(0xc8800000, 0x2000)` é o caminho certo (não `pci_iomap(pdev, 2, ...)`, que retorna tamanho 0 nesse device).

**Resultado negativo:** Condição `(p0 & 0x80800000) == 0x80800000` FALHA com os valores reais → bloco grande de calibração MDIO nunca executa (inócuo).

**CRASH:** Módulo travou, `eth0` sumiu.

**Causa raiz identificada (revisão estática, sem precisar de novo teste ao vivo):** **stack buffer overflow real** em `mts_phy_calibration()`, bloco "calibration loop via 0x1bc-0x1d4" (mts.c linhas 701-771):
```c
u32 calib_tbl[32];   // válido: índices 0-31 (128 bytes)
u32 calib_msk[32];
ci = 0x22;            // 34 — já fora dos limites
calib_tbl[ci + 2] = ...   // [36] OOB
calib_tbl[ci | 9]  = ...  // [43] OOB
calib_tbl[ci | 8]  = ...  // [42] OOB
ci = ((ci | 8) + 0xe) | 2;  // 58
calib_tbl[ci + 7]  = ...  // [65] OOB — 132 bytes além do fim do array
```
Origem do erro: `ci = 0x22` no Orbis é um **offset em bytes dentro do softc gigante** (struct de milhares de bytes, ver `consolidado/RE_KERNEL_GBE_ATTACH.md`), não um índice de array `u32[32]` local — a tradução tratou um offset de struct como índice de array, gerando overflow de stack de até 132 bytes.

**Plano de correção completo:** ver `memory/PLANO-CORRECAO-BAR2-PHY-CALIB-2026-07-23.md`. Resumo: isolar o bloco da tabela atrás de `enable_phy_calib_table=false` (novo module param, default off), instrumentar com `dev_info()` pre/post as ~7 escritas de registrador nunca validadas ao vivo (0x78, 0x08, 0x0c, 0x1d4, 0x10, 0x33001e via MDIO, page 0), e só reimplementar a tabela depois de RE dedicada (não adivinhação de offsets).

**Status (2026-07-23):** ✅ **CORRIGIDO E IMPLEMENTADO.** 
- Criado o parâmetro `enable_phy_calib_table` (default `false`), isolando o bloco de estouro de pilha.
- Adicionados os logs de diagnósticos pre/post para monitoramento passivo das escritas.
- Renomeados os macros para `MTS_GLUE_CALIB_*`.
- Módulo recompilado e BTF removido com sucesso em `drivers_mts/build/mts.ko`. Pronto para o Teste ao Vivo #1 da Seção 5.2.

---

## Teste ao Vivo #1 — Validação da Correção do Overflow de Stack (2026-07-23, 14:30 UTC)

**Objetivo:** Confirmar que o módulo corrigido carrega sem crash.

**Setup:**
- Módulo: `drivers_mts/build/mts.ko` (compilado, BTF removido)
- Parâmetros: `stage=4`, `enable_phy_calib=1`, `enable_phy_calib_table=0` (padrão — CORREÇÃO APLICADA)

**Execução:** Download via HTTP, `rmmod` antigo, `insmod` novo → SUCCESS

**RESULTADO: ✅ TESTE #1 PASSOU**

### Dados Coletados:

**1. Mapeamento de BAR2/Glue:**
```
mts 0000:00:14.1: glue (bpcie) mapeado: phys=0xc8800000
PHY calibration: BAR2 params: 0x6c=0x331250b5 0x68=0x000050b4 0x60=0x000050a4 0x5c=0x33125095 0x100=0x10000201
```
✅ Valores reais lidos com sucesso

**2. Pré-condição de Calibração:**
- p0 = 0x331250b5
- (p0 & 0x80800000) = 0x00000000 ≠ 0x80800000
- **Bloco grande de calibração MDIO NUNCA EXECUTA** (inócuo, conforme esperado)

**3. Bloco de Tabela (Principal Causa do Crash):**
```
PHY calibration table (0x1bc-0x1d4): desabilitada via module param (default)
```
✅ **Stack overflow eliminado** — bloco isolado e desabilitado

**4. Instrumentação pre/post (Todas as 7 escritas registradas):**
```
pre  0x04=0x00000b18 → post 0x04=0x00000b18
pre  0x78=0x00000000 → post 0x78=0x00000000
pre  0x0c=0x03b0030c → post 0x0c=0x03b0030c
pre  0x08=0x0f597c00 → post 0x08=0x0f597c00
pre  0x1d4=0x00000001 → post 0x1d4=0x00000001
pre  0x10=0x00000085 → post 0x10=0x00000085
pre  Page 0=0x0000
pre  MDIO 0x33001e=0x0000
```
✅ Todas as operações registradas (valores pré/pós iguais = dados diagnósticos válidos)

**5. Status Final:**
```
PHY calibration: concluída
MAC lido da SPM: 2c:cc:44:3f:69:5f
mts registrado como eth0, MAC 2c:cc:44:3f:69:5f
```
✅ **Nenhum crash, nenhum oops, eth0 presente**

**6. Status de Link (Esperado: DOWN)**
```
ip link show eth0 → state DOWN
Registrador 0x04 (LINK_STATUS) = 0x00000b18 (bit[0]=0, link DOWN)
```
⚠️ Link continua DOWN (bloqueador é o PHY, não o driver)

| Critério | Resultado |
|---|---|
| Crash | ❌ NÃO houve ✅ |
| Overflow isolado | ✅ Confirmado |
| eth0 presente | ✅ SIM |
| Calibração iniciada | ✅ SIM |
| Tabela desabilitada | ✅ SIM |
| Link detectado | ❌ NÃO (esperado, próxima investigação) |

**Conclusão:** ✅ **BLOQUEADOR PRIMÁRIO (CRASH) ELIMINADO**. Módulo estável, pronto para Testes #2/#3 focando em por que o PHY não detecta link.


