---
name: teste-2-resultado-completo
description: Resultado completo do Teste #2 — investigação de link detection
metadata:
  type: project
---

# 📊 Teste #2 — Resultado Completo

**Data:** 2026-07-23 15:15 UTC  
**Status:** ⚠️ Parcialmente Concluído (Fase 3 interrompida)

---

## Fase 1: MDIO Response Collection — ✅ CONCLUÍDA

### Achado Crítico
```
MDIO lê SEMPRE 0x0000 (nunca muda, não hay timeout)
```

**Registrador 0x33001e:** 0x0000 (read-only ou não responde)
**Page 0:** 0x0000 (read-only ou não responde)

**Conclusão:** 
🔴 **PHY NÃO ESTÁ RESPONDENDO em Clause 45 MDIO**

---

## Fase 2: Test enable_phy_calib_table=1 — ⚠️ NÃO COMPLETADA

**Tentativa:** `insmod /tmp/mts.ko stage=4 enable_phy_calib_table=1`
**Resultado:** Módulo travou/crash
**Implicação:** Ativar a tabela com o código atual causa instabilidade

**Análise:**
- A pré-condição `(p0 & 0x80800000)` falha, então bloco de tabela não executa
- Mas carregar com `enable_phy_calib_table=1` causa problema (pode ser outro bug no código)
- PS4 ficou inacessível, provavelmente rebootou ou kernel panic

---

## Fase 3: Interface UP Test — ❌ NÃO COMPLETADA

**Status:** PS4 inacessível (provável crash durante Fase 2)
**Esperado (sem Fase 2):** Interface consegue ir UP com carrier OFF
**Ação necessária:** Aguardar recuperação do PS4 ou power cycle manual

---

## Resumo de Achados

| Descoberta | Evidência | Implicação |
|---|---|---|
| MDIO Clause 45 não responde | Leitura sempre 0x0000 | PHY pode estar em Clause 22 ou power-down |
| Pré-condição bloqueia tabela | (p0 & 0x80800000) = 0 | Bloco MDIO nunca executa (já confirmado) |
| enable_phy_calib_table=1 causa crash | PS4 inacessível após tentativa | Bug no código da tabela mesmo desabilitada? |
| Link continua DOWN | 0x04 = 0x00000b18 | Esperado (sem calibração funcionando) |

---

## Conclusões Principais

### 1. **PHY não responde em Clause 45**
- MDIO reads sempre retornam 0x0000
- Não há timeouts (operações completam)
- PHY provavelmente usa Clause 22 (MII) ou está em power-down

### 2. **Código de tabela instável**
- Carregar com `enable_phy_calib_table=1` causa crash
- Problema não é a pré-condição (que bloqueia o bloco)
- Pode haver outro bug no código de tabela mesmo que nunca execute

### 3. **Bloco grande de calibração MDIO é irrelevante**
- Pré-condição falha garante que nunca executa
- Remover essa seção não faria diferença (confirmado por Teste #1)

---

## Próximos Passos

### Imediato (após PS4 recuperar)
1. **Não** ativar `enable_phy_calib_table=1` (causa crash)
2. **Investigar** por que `enable_phy_calib_table=1` causa crash
3. **Implementar** Clause 22 (MII) fallback para MDIO

### Investigação Clause 22
Conforme seção 4 de PLANO-CORRECAO-BAR2-PHY-CALIB-2026-07-23.md:
- PHY responde em Clause 22, não Clause 45 (MII vs Clause 45)
- Diferentes opcodes e formato no registrador BAR0+0x00
- Pode ser alternativa viável se Clause 45 não funcionar

---

## Status do Projeto

**Bloqueador Primário (Crash):** ✅ ELIMINADO (Teste #1)  
**Bloqueador Secundário (Link Detection):** 🔴 IDENTIFICADO (PHY não responde Clause 45)  
**Próxima Investigação:** Implementar Clause 22 fallback  

---

## Recomendação

**Aguardar PS4 recuperar, depois:**

1. **Consertar bug em enable_phy_calib_table** (por que causa crash?)
2. **Implementar Clause 22** para MDIO (conforme plano de correção)
3. **Teste #3:** Validar se Clause 22 faz link aparecer

---

**Documentação Relacionada:**
- [teste-2-fase1-resultado-2026-07-23.md](teste-2-fase1-resultado-2026-07-23.md) — Dados detalhados Fase 1
- [plano-teste-2-link-investigation-2026-07-23.md](plano-teste-2-link-investigation-2026-07-23.md) — Plano original
- [PLANO-CORRECAO-BAR2-PHY-CALIB-2026-07-23.md](PLANO-CORRECAO-BAR2-PHY-CALIB-2026-07-23.md) — Seção 4: Investigação Clause 22
