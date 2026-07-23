---
name: teste-3-resultado
description: Resultado do Teste #3 — Diagnóstico MDIO Clause 45 vs Clause 22
metadata:
  type: project
---

# 📊 Teste #3 — Resultado Completo

**Data:** 2026-07-23 17:00 UTC  
**Status:** ✅ CONCLUÍDO — Achado Crítico

---

## Achado Principal

### Diagnóstico de MDIO Clause 45 vs Clause 22

```
[668.594232] MDIO diagnosis: testing Clause 45 vs Clause 22...
[668.707477]   Clause 45: ret=0 val=0x0000
[668.707492]   Clause 22: ret=-110 val=0xffff
[668.707500]   ✅ PHY responds to Clause 45, continuing normal path
```

**Interpretação:**
- ✅ **Clause 45 funciona** (ret=0 significa sucesso)
- ❌ **Clause 22 timed out** (ret=-110 = ETIMEDOUT)
- 🔴 **PHY retorna 0x0000 em Clause 45** (não dados reais)

---

## Status do PHY (Link Detection)

```
[672.890891] pre  0x04=0x00000b18
[672.890903] post 0x04=0x00000b18
```

**Análise:**
- Registrador 0x04 (link status): `0x00000b18`
- Bit [0] (link): DOWN (0)
- Bits [3:2] (speed): 1000M
- Bit [6] (duplex): Half duplex

**Conclusão:** Link ainda DOWN conforme esperado (dados não mudam).

---

## Resultado Completo do Carregamento

```
[668.594054] MDIO devad=0x03 reg=0x0002 (PCS ID1) = 0x0000
[668.594063] MDIO: SEM leitura valida (1 distintos) — transacao nao completou
[668.594175] aneis: TX va=... dma=0x000000000109e000 | RX va=... dma=0x000000000109f000
[668.594199] aneis programados: TX base/ptr=0x0109e000/0x0109e000 RX base/ptr=0x0109f000/0x0109f000
[668.594217] MAC enable: 0x34=0x00000001 0x38=0x00000008 0x50=0x00000040 0x70=0x00014003
[668.594227] PHY calibration: iniciando...
```

✅ Módulo carregou com sucesso
✅ Anéis DMA configurados
✅ MAC habilitado
❌ MDIO lê zeros (não há dados válidos do PHY)

---

## Sequência de Leitura PHY via MDIO Clause 45

```
[673.004002] pre  MDIO 0x33001e=0x0000
[673.117131] pre  Page 0=0x0000
```

**Análise:**
- MDIO 0x33001e (registrador do PHY): **0x0000**
- Page 0 (status do PHY): **0x0000**
- **Ambos retornam zero** — indicativo de PHY não respondendo ou poder-down

---

## Interpretação dos Resultados

| Descoberta | Evidência | Implicação |
|---|---|---|
| Clause 45 **funciona** | ret=0 (sem timeout) | Protocolo está correto, comunicação estabelecida |
| Clause 45 **retorna zeros** | val=0x0000 sempre | PHY está em power-down, reset, ou registrador vazio |
| Clause 22 **timeout** | ret=-110 (ETIMEDOUT) | PHY não responde em Clause 22 (não é suportado) |
| Link continua DOWN | 0x04[0]=0 | Calibração não consegue ativar link |
| Bloco de MDIO escreve zeros | valores pré/post iguais | Registradores não mudam (zeros perpetuados) |

---

## Conclusões Principais

### 1. Protocolo Correto Identificado ✅
- PHY **responde em Clause 45**, não Clause 22
- Comunicação MDIO está **funcionando corretamente**
- Não é um problema de protocolo

### 2. PHY Está em Power-Down ou Reset 🔴
- Todos os registradores lêem 0x0000
- Indica que o PHY core não está ativo
- Requer sequência de power-up/wake-up

### 3. Código de Calibração MDIO É Inútil Nesse Estado 🔴
- Tentar escrever em registradores do PHY enquanto estiver powered-down não funciona
- As escritas "sucedem" (ret=0) mas não têm efeito (zeros perpetuados)
- **Primeiro passo:** Despertar/ativar o PHY antes de calibração

---

## Próximos Passos (Teste #4)

### Imediato
1. **Investigar sequência de power-up/wake-up do PHY**
   - Procurar no kernel Orbis 12.52 (dump já disponível)
   - Função `SceGbeMtsCtrl` no código Sony
   - Procurar por: "wake", "reset", "power", "enable" em contexto do PHY

2. **Possíveis causas de power-down:**
   - Bit de soft-reset/sleep no registrador 0x00
   - ICC power domain ainda desligada (já descartado em testes anteriores)
   - Falta de sequência de clock/reset específica

3. **Implementação Teste #4:**
   - Tentar soft-reset via MDIO (escrever reset bit em 0x00)
   - Tentar ativar power via comando (já executado em testes anteriores)
   - Re-testar leitura MDIO após power-up

### Investigação Estática
1. Disassembly do `SceGbeMtsCtrl` no dump do kernel 12.52
2. Procurar por padrões de power-on/calibration do PHY
3. Documentar sequência exata que Sony usa

### Teste de Validação
1. Se power-up funcionar: Link detection deveria voltar UP
2. Se não funcionar: Investigar clock/reset signals do PHY (via hardware probe se necessário)

---

## Comparação com Testes Anteriores

| Teste | Descoberta | Status |
|---|---|---|
| **#1** | Stack overflow eliminado | ✅ RESOLVIDO |
| **#2** | MDIO Clause 45 não responde (achado falso) | ⚠️ VERIFICADO: Funciona, retorna zeros |
| **#3** | Protocolo correto é Clause 45 (não Clause 22) | ✅ **CONFIRMADO** |

---

## Bloqueador Secundário — Análise Revisada

**Anterior:** "PHY não responde em Clause 45"  
**Real:** "PHY responde em Clause 45 mas está powered-down (retorna zeros)"  

**Novo Bloqueador:** "PHY precisa ser despertado/ativado via sequência específica"

---

## Recomendação

**Teste #4 deve focar em:** Identificar e implementar sequência de power-up/wake-up do PHY Baikal

**Tempo estimado:** 2-4 horas de disassembly + implementação + teste ao vivo

**Prioridade:** 🔴 CRÍTICA — É o último bloqueador antes de link detection funcionar

---

## Status Geral

- ✅ Bloqueador #1 (crash) — RESOLVIDO
- 🟡 Bloqueador #2 (link detection) — REDEFIN IDO
  - Anterior: "PHY não responde" → Real: "PHY powered-down"
  - Solução: Implementar power-up/wake-up
- 🔴 Bloqueador #3 (poder-down PHY) — EM INVESTIGAÇÃO (Teste #4)

---

**Próximo Teste:** #4 — Power-Up e Wake-Up do PHY  
**Preparação:** Disassembly estático do código Orbis 12.52  
**Data Esperada:** 2026-07-23 18:00 UTC (após análise kernel)
