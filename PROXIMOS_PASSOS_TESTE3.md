# 🎯 PRÓXIMOS PASSOS — Teste #3 (Clause 22 Fallback)

**Status:** Módulo compilado e pronto para teste ✅

---

## Situação Atual

### ✅ Completo
- Implementação de MDIO Clause 22 (MII) adicionada ao `mts.c`
- Diagnóstico automático de Clause 45 vs Clause 22 implementado
- Módulo compilado com sucesso via Docker (toolchain correto)

### ⏳ Aguardando
- **Transferência do módulo ao PS4 via SSH**
- **Execução do teste ao vivo**

### 🔴 Bloqueador Atual
- SSH para `root@192.168.6.128` ou `root@192.168.0.2` está pedindo senha
- Credencial SSH necessária para prosseguir

---

## Instruções de Teste

### Passo 1: Transferir Módulo (Requer SSH)
```bash
# Opção A: Via WiFi (192.168.6.128)
scp drivers_mts/build/mts.ko root@192.168.6.128:/tmp/

# Opção B: Via Ethernet (192.168.0.2) — se disponível
scp drivers_mts/build/mts.ko root@192.168.0.2:/tmp/
```

**Localização do módulo:**
```
/mnt/t/downloads/PS4/linux_in_ps4/drivers_mts/build/mts.ko
```

### Passo 2: Carregar Módulo (após transferência)
```bash
ssh root@192.168.6.128 "insmod /tmp/mts.ko stage=4"
```

### Passo 3: Capturar Diagnóstico
```bash
ssh root@192.168.6.128 "dmesg | tail -50 | grep -A 20 'MDIO diagnosis'"
```

---

## O que Esperar na Saída

### Cenário A: PHY Responde em Clause 22 ✅
```
[...] MDIO diagnosis: testing Clause 45 vs Clause 22...
[...] Clause 45: ret=0 val=0x0000
[...] Clause 22: ret=0 val=0xXXXX  ← valor real (não zero)
[...] ✅ PHY responds to Clause 22 (MII), will use fallback
```
**→ Próximo:** Implementar fallback automático na calibração

### Cenário B: PHY Não Responde em Nenhum ❌
```
[...] MDIO diagnosis: testing Clause 45 vs Clause 22...
[...] Clause 45: ret=... val=0x0000
[...] Clause 22: ret=... val=0x0000
[...] ⚠️  PHY not responding to either Clause 45 or Clause 22!
```
**→ Próximo:** Investigar se PHY está powered-down ou em reset

### Cenário C: Ambos Retornam Dados ℹ️
```
[...] Clause 45: ret=0 val=0xXXXX
[...] Clause 22: ret=0 val=0xYYYY
[...] ⚠️  Both Clause 45 and Clause 22 return data...
```
**→ Próximo:** Analisar qual protocolo é correto para esse PHY

---

## Documentação de Referência

- **Implementação Detalhada:** `memory/teste-3-clause22-implementacao-2026-07-23.md`
- **Teste #2 (Achado):** `memory/teste-2-resultado-completo-2026-07-23.md`
- **Plano Original:** `memory/PLANO-CORRECAO-BAR2-PHY-CALIB-2026-07-23.md`

---

## Falhas Esperadas & Soluções

| Problema | Solução |
|---|---|
| SSH: Permission denied | Fornecer password de root ou SSH key |
| SSH: No route to host | Tentar WiFi (192.168.6.128) ou confirmar IP |
| Módulo não carrega | Remover versão antiga: `ssh root@IP "rmmod mts; sleep 2"` |
| dmesg não mostra diagnosis | Tentar: `ssh root@IP "journalctl -u kernel\|tail -50"` |

---

## Status de Bloqueadores

| Bloqueador | Status | Ação |
|---|---|---|
| Crash do módulo | ✅ RESOLVIDO (Teste #1) | N/A |
| PHY não responde Clause 45 | ✅ IDENTIFICADO (Teste #2) | Teste #3 em progresso |
| SSH acesso ao PS4 | 🔴 BLOQUEADO | Credential necessária |

---

## Próximo Marco (após Teste #3)

Após confirmar qual protocolo funciona:
1. Implementar fallback automático na função `mts_phy_calibration()`
2. Se Clause 22: Refazer calibração usando Clause 22
3. Se nenhum: Investigar power-up/reset do PHY

---

**Criado:** 2026-07-23 16:45 UTC  
**Módulo pronto:** `/mnt/t/downloads/PS4/linux_in_ps4/drivers_mts/build/mts.ko`
