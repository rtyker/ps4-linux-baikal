---
name: plano-teste-2-link-investigation
description: Plano do Teste #2 — investigar por que link não é detectado
metadata:
  type: project
---

# 🔍 Teste #2 — Investigação de Link Detection

**Objetivo:** Identificar por que o registrador 0x04 continua com bit[0]=0 (link DOWN) mesmo com cabo conectado

**Status do Teste #1:** ✅ Passou (crash eliminado, módulo estável)

---

## Análise Prévia

**Problema:** Registrador 0x04 = `0x00000b18` (bit[0]=0, link DOWN)

**Dados de Teste #1:**
- BAR2 parâmetros lidos com sucesso
- Pré-condição para MDIO calibration falha: `(p0 & 0x80800000) = 0 ≠ 0x80800000`
- Bloco grande de calibração MDIO **não executa**
- Operações pós-if (page ops, MAC address, etc.) **executam**
- Link ainda DOWN

**Hipóteses a Testar:**

1. **Hipótese A:** Bloco grande de calibração MDIO é **necessário** para link aparecer
   - Ação: Ativar `enable_phy_calib_table=1` (ativaria o bloco se a pré-condição passasse)
   - Problema: pré-condição falha localmente, então não ajudaria
   - Alternativa: Implementar RE correta da tabela primeiro

2. **Hipótese B:** Bloco de "sempre roda" (page ops, MDIO 0x33001e, page 0) é insuficiente
   - Ação: Coletar MDIO responses detalhadas
   - Verificar se leituras MDIO retornam 0x0000 (residual) ou valores válidos

3. **Hipótese C:** PHY está respondendo no Clause 22, não Clause 45
   - Ação: Testar acesso via Clause 22
   - Fallback se Clause 45 não funciona

4. **Hipótese D:** PHY precisa ser trazido de uma condição de reset/power-down
   - Ação: Verificar se há bit de "soft reset" ou "power down" em 0x04 que precise ser limpo
   - Atualmente: escrita é `link_save & 0x7fffcfff` (limpa bits altos)

---

## Plano de Teste #2

### Fase 1: Coleta de Dados MDIO (Low Risk)

**Objetivo:** Verificar se o PHY está respondendo (ou retornando residual 0x0000)

**Comandos:**
```bash
# Ativar módulo
insmod /tmp/mts.ko stage=4

# Coletar MDIO responses
sshpass -p ps4 ssh root@192.168.6.128 "dmesg | grep 'MDIO 0x33001e\|Page 0\|Page 4' | tail -10"

# Verificar se há "timeout" ou "MDIO wait" no dmesg
sshpass -p ps4 ssh root@192.168.6.128 "dmesg | grep -i 'timeout\|mdio.*retry\|wait.*fail'"
```

**Esperado:**
- Se PHY responde: MDIO reads retornarão valores != 0x0000/0xffff
- Se PHY não responde: sempre 0x0000 ou 0xffff, possível "timeout" em dmesg

**Resultado Esperado:**
- ✅ Valores válidos → PHY funciona, problema é na sequência de calibração
- ❌ Sempre 0x0000 → PHY não responde, provavelmente Clause 22 vs 45, ou PHY completamente desligado

### Fase 2: Verificar se Bloco de Tabela é Necessário (Medium Risk)

**Objetivo:** Testar se ativar `enable_phy_calib_table=1` faria diferença (mesmo que bloco não execute)

**Problema:** Pré-condição falha localmente, então bloco de tabela **nunca executaria** mesmo com flag ON
- Mas vamos verificar se há algum efeito colateral de ter o código presente

**Comando:**
```bash
rmmod mts
insmod /tmp/mts.ko stage=4 enable_phy_calib_table=1
sleep 2
dmesg | tail -20
```

**Esperado:**
- Se bloco tiver efeito: dmesg mostraria "loop N iteracoes concluido"
- Se pré-condição falha impede: mostraria "desabilitada" ainda (pré-condição falha antes da flag)
- Carrier status: provavelmente continua 0

**Resultado Esperado:**
- ❌ Nenhum efeito (bloco nunca executa) → confirma que pré-condição é o bloqueador

### Fase 3: Testar eth0 Interface (Low Risk, Informativo)

**Objetivo:** Verificar se interface consegue operar mesmo com carrier OFF

**Comando:**
```bash
sshpass -p ps4 ssh root@192.168.6.128 <<'EOTEST'
  ip link set eth0 up
  sleep 1
  ip addr add 192.168.0.100/24 dev eth0
  sleep 1
  ping -c 2 192.168.0.1
  dmesg | tail -5
EOTEST
```

**Esperado:**
- Interface pode ir `UP` mesmo com carrier OFF (é só um aviso do kernel)
- Ping falha (nenhum link físico)
- Dmesg limpo (nenhum erro de interface)

**Resultado Esperado:**
- ✅ Interface operational (problema é só carrier detection, não operação)
- ❌ Interface problemas (issue mais profunda)

---

## Decisão Tree

```
Teste #2 Fase 1: MDIO Response?
├─ SIM (valores válidos)
│  └─ Fase 2: Testar tabela com flag ON
│     └─ Link muda? 
│        ├─ SIM → investigar pré-condição (p0 & 0x80800000)
│        └─ NÃO → Fase 3 (testar interface) → determinar se só link detection ou mais
│
└─ NÃO (sempre 0x0000)
   └─ PHY não responde
      └─ Próximo: Investigar Clause 22 fallback (seção 4 PLANO-CORRECAO)
```

---

## Recursos Necesarios

- Módulo compilado: `drivers_mts/build/mts.ko` (já pronto)
- SSH acesso ao PS4: `192.168.6.128` (já funciona)
- HTTP server: `python3 -m http.server 8888` no host (já rodando)

---

## Esperado vs. Observado (Teste #1 baseline)

| Item | Teste #1 | Esperado Teste #2 |
|---|---|---|
| Módulo load | ✅ OK | ✅ OK (mesmo) |
| MDIO responses | 0x0000/unknown | ? Investigar |
| Link (0x04 bit[0]) | 0 | 0 (provável) |
| Carrier | OFF | OFF (provável) |
| Interface UP | Não testado | Teste em Fase 3 |

---

## Próximas Decisões (Pós Teste #2)

**Se MDIO responde (valores válidos):**
→ Problema é na sequência de calibração, não no PHY
→ Investigar por que pré-condição `(p0 & 0x80800000)` falha
→ Possível: valores de parâmetros BAR2 não são esperados
→ Ação: Comparar com valores do dump Orbis

**Se MDIO não responde (0x0000/0xffff):**
→ PHY não está respondendo em Clause 45
→ Investigar Clause 22 fallback ou power-up sequencing
→ Ação: Seção 4 do PLANO-CORRECAO (investigação Clause 22)

**Se interface consegue ficar UP:**
→ Problema é **puramente link detection**, não operacional
→ Permite isolamento da causa (MDIO, calibração, registrador)

---

## Timing Estimado

- **Fase 1:** ~2 min (coleta de logs)
- **Fase 2:** ~3 min (teste de flag)
- **Fase 3:** ~2 min (teste interface)
- **Total:** ~7 min + análise

---

**Status:** Pronto para execução quando autorizado  
**Risco:** Baixo (sem novas escritas, só leitura + interface UP)  
**Impacto:** Direto na causa raiz de por que link não funciona
