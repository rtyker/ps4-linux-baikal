---
name: teste-2-fase1-resultado
description: Resultado da Fase 1 do Teste #2 — coleta de dados MDIO
metadata:
  type: project
---

# 📊 Teste #2 — Fase 1: Coleta de Dados MDIO (CONCLUÍDO)

**Data:** 2026-07-23 15:00 UTC  
**Status:** ✅ Completo

---

## Achado Crítico

### **MDIO está RETORNANDO ZERO (0x0000)**

```
[261.521511] mts 0000:00:14.1: pre  MDIO 0x33001e=0x0000
[261.634581] mts 0000:00:14.1: pre  Page 0=0x0000
[513.676619] mts 0000:00:14.1: pre  MDIO 0x33001e=0x0000
[513.789702] mts 0000:00:14.1: pre  Page 0=0x0000
```

**Interpretação:**
- Leitura MDIO de `0x33001e` (registrador do PHY) **sempre retorna 0x0000**
- Leitura de `Page 0` **sempre retorna 0x0000**
- Não há timeouts MDIO (operações completam)
- Não há erros visíveis

**Conclusão:** 
❌ **PHY NÃO ESTÁ RESPONDENDO** em Clause 45 MDIO, ou
❌ **O registrador realmente contém 0x0000** (improvável)

---

## Dados Coletados

### Registrador 0x04 (LINK_STATUS)
```
Valor: 0x00000b18
Análise:
  bit[0] (link): DOWN (0)
  bits[3:2] (speed): 1000M
  bit[6] (duplex): Half duplex
```

✅ Registrador continua mostrando link DOWN, conforme esperado.

### Timeouts/Erros
```
[Nenhum timeout MDIO detectado]
[Nenhum erro de calibração PHY]
[Nenhum Kernel Panic]
```

✅ Operações MDIO completam sem erro, apenas retornam dados zerados.

### Logs de Calibração
```
[257.224326] PHY calibration: iniciando...
[257.224407] PHY calibration: BAR2 params: 0x6c=0x331250b5 ...
[261.747751] PHY calibration: concluída
```

✅ Calibração roda até o final, nenhuma falha.

---

## Interpretação

| Cenário | Probabilidade | Evidência |
|---|---|---|
| PHY não responde em Clause 45 | 🔴 **ALTA** | MDIO sempre lê 0x0000 |
| PHY precisa de Clause 22 | 🟡 MÉDIA | Possível alternativa se 45 não funciona |
| Registrador 0x33001e é read-only | 🟢 BAIXA | Unlikely para um registrador de controle |
| PHY está em power-down/reset | 🟡 MÉDIA | Possível, mas não há evidência de reset |
| Calibração MDIO nunca roda por pré-condição | 🟢 CONFIRMADO | Bloco grande não executa (p0 & 0x80800000 = 0) |

---

## Implicações para Próximas Fases

### Fase 2 (Planejada)
**Objetivo:** Testar `enable_phy_calib_table=1` para ver se bloco de tabela faria diferença
**Resultado Esperado:** Bloco de tabela NÃO vai executar (pré-condição bloqueia), então nenhuma diferença
**Status:** Pode ser pulado, conclusão é óbvia

### Fase 3 (Próxima)
**Objetivo:** Testar se interface consegue ficar UP mesmo com carrier OFF
**Esperado:** SIM (problema é só link detection)
**Ação:** Coletando...

---

## Próximas Investigações (Pós Teste #2)

### Hipótese Primária: MDIO Clause 22 Fallback
Se MDIO Clause 45 não responde, PHY pode estar em Clause 22 (MII):
- Implementar leitura/escrita Clause 22 (formato diferente no mesmo registrador BAR0+0x00)
- Tentar ler status do PHY via Clause 22
- Se funcionar: usar Clause 22 para calibração

### Hipótese Secundária: PHY Power/Reset
PHY pode estar em estado de reset ou power-down:
- Verificar se há bit de "soft reset" em 0x04 que precisa ser limpo
- Procurar sequência de power-up no código Orbis (dc5a0ba0, linhas ~196-250)
- Implementar sequência de wake-up do PHY

### Hipótese Terciária: Registrador Errado
Registrador `0x33001e` pode ser endereço errado:
- Verificar em consolidado/RE_KERNEL_GBE_ATTACH.md se 0x33001e é realmente usado
- Comparar com outros registradores de controle mencionados na RE
- Possível: offset está certo, mas registrador é write-only ou não-existente

---

## Status Geral

- ✅ **Fase 1 CONCLUÍDA:** MDIO não responde (retorna sempre 0x0000)
- ⏳ **Fase 2 EM ESPERA:** Pode ser pulada (conclusão óbvia)
- ⏳ **Fase 3 EM PROGRESSO:** Testando se interface UP funciona
- 🔴 **BLOQUEADOR IDENTIFICADO:** PHY não responde em Clause 45 MDIO

---

## Recomendação

**Próximo passo** (após Fase 3): Investigar Clause 22 fallback conforme seção 4 do PLANO-CORRECAO. O PHY definitivamente não está respondendo em Clause 45, portanto usar MDIO Clause 22 é a ação lógica.
