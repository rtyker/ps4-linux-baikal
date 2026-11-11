---
name: teste-1-resumo-executivo
description: Resumo executivo do Teste ao Vivo #1 — validação da correção do stack overflow
metadata:
  type: project
---

# 📊 Teste ao Vivo #1 — Resumo Executivo

**Data:** 2026-07-23 14:30 UTC  
**Objetivo:** Confirmar que o crash por stack overflow foi eliminado  
**Resultado:** ✅ **PASSOU com sucesso**

---

## O que foi testado

| Componente | Teste | Resultado |
|---|---|---|
| **Compilação** | Módulo compilado sem warnings | ✅ OK |
| **Carregamento** | `insmod mts.ko stage=4` | ✅ OK (sucesso imediato) |
| **Crash detection** | `eth0` presente após insmod | ✅ OK (sem crash) |
| **dmesg** | Nenhum oops/panic/warning | ✅ OK (limpo) |
| **BAR2 mapeamento** | `ioremap(0xc8800000, 0x2000)` | ✅ OK (valores reais lidos) |
| **Parâmetros glue** | 5 offsets de calibração | ✅ OK (`0x6c=0x331250b5`, etc.) |
| **Pré-condição** | `(p0 & 0x80800000) == 0x80800000` | ✅ FALHA (esperado, bloco MDIO não roda) |
| **Stack overflow isolamento** | Bloco de tabela via `enable_phy_calib_table` | ✅ OK (desabilitado por padrão) |
| **Instrumentação** | Logs pre/post de 7 registradores | ✅ OK (todos registrados) |

---

## Dados Detalhados

### Carregamento do Módulo
```bash
$ insmod /tmp/mts.ko stage=4
[257.223650] mts 0000:00:14.1: glue (bpcie) mapeado: phys=0xc8800000 va=00000000dfccb1cd
[257.224326] mts 0000:00:14.1: PHY calibration: iniciando...
[257.224407] mts 0000:00:14.1: PHY calibration: BAR2 params: 0x6c=0x331250b5 0x68=0x000050b4 0x60=0x000050a4 0x5c=0x33125095 0x100=0x10000201
[261.408354] mts 0000:00:14.1: pre  0x04=0x00000b18
[261.408368] mts 0000:00:14.1: post 0x04=0x00000b18
...
[261.747745] mts 0000:00:14.1: PHY calibration table (0x1bc-0x1d4): desabilitada via module param (default)
[261.747751] mts 0000:00:14.1: PHY calibration: concluída
[261.748318] mts 0000:00:14.1: mts registrado como eth0, MAC 2c:cc:44:3f:69:5f
```

✅ **Sem crashes, sem warnings, sequência de inicialização completa**

### Parâmetros BAR2/Glue Lidos
```
0x6c (p0) = 0x331250b5  → Pré-condição: (0x331250b5 & 0x80800000) = 0x00 ≠ 0x80800000 ❌
0x68 (p1) = 0x000050b4
0x60 (p2) = 0x000050a4
0x5c (p3) = 0x33125095
0x100(p4) = 0x10000201
```

**Interpretação:** Pré-condição falha (esperado, conforme análise estática). Bloco grande de calibração MDIO **nunca executa**. Inócuo.

### Instrumentação pre/post (Validação de Diagnóstico)
```
[261.408354-368] pre/post 0x04 (LINK_STATUS)   → 0x00000b18 (bit[0]=0, link DOWN)
[261.408377-386] pre/post 0x78                 → 0x00000000
[261.521511]     pre  MDIO 0x33001e            → 0x0000
[261.634581]     pre  Page 0                   → 0x0000
[261.747679-690] pre/post 0x0c                 → 0x03b0030c
[261.747700-708] pre/post 0x08                 → 0x0f597c00
[261.747715-720] pre/post 0x1d4                → 0x00000001
[261.747728-735] pre/post 0x10                 → 0x00000085
```

✅ **Todas as operações executadas e registradas em dmesg**  
✅ **Valores pré/pós iguais = dados para análise futura (nenhuma mudança por essas escritas)**

### Status de Link (Esperado: DOWN)
```bash
$ cat /sys/class/net/eth0/carrier
(arquivo não legível — normal com carrier OFF)

$ ip link show eth0
7: eth0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT

Registrador 0x04 = 0x00000b18
  bit[0] = 0 → Link DOWN (esperado)
```

---

## Conclusões

### ✅ Objetivo Atingido: CRASH ELIMINADO
- **Antes (Teste pós-implementação primeira):** Módulo carregava, calibração rodava, `eth0` sumia (crash)
- **Depois (Teste #1):** Módulo carregado, calibração rodou, **eth0 continua presente** (sem crash)
- **Causa:** Stack buffer overflow em `calib_tbl[32]` (índices até 65) foi isolado atrás de `enable_phy_calib_table=false`

### ✅ BAR2/Glue Mapeamento: FUNCIONAL
- Ioremap direto de `0xc8800000` funciona
- Valores reais de calibração lidos com sucesso
- Rename de macros (`MTS_BAR2_CALIB_*` → `MTS_GLUE_CALIB_*`) aumenta clareza

### ❌ Link Detection: AINDA DESATIVADO
- **Causa:** Pré-condição `(p0 & 0x80800000) == 0x80800000` falha com valores ao vivo
- **Impacto:** Bloco grande de calibração MDIO não executa
- **Status:** Planejado para Teste #2/#3 investigar por que link permanece DOWN

### ✅ Instrumentação: COMPLETA E FUNCIONAL
- Todas as 7 escritas de registrador registradas em dmesg
- Pre/post values para análise
- Pronto para coleta de dados no Teste #2

---

## Próximos Passos Recomendados

### **Teste #2 (Opcional — Coleta de Dados Expandida)**
- Testar com `enable_phy_calib=0` para ver se a calibração é necessária
- Coletar MDIO responses (atualmente sempre 0x0000)
- Verificar se há timeout em operações MDIO

### **Teste #3 (Crítico — Investigação de Link)**
- `ip link set eth0 up`
- `ethtool eth0` (verificar status)
- Ping para testar RX/TX mesmo com carrier OFF
- Diagnosticar se problema é só detecção ou também operacional

### **Investigação de Clause 22 vs 45**
- Se carrier continuar OFF após Teste #3
- Considerar implementação de fallback para Clause 22 (conforme seção 4 do PLANO-CORRECAO)

---

## Arquivos Modificados
- `drivers_mts/mts.c` — Isolamento de tabela + instrumentação
- `drivers_mts/mts.h` — Rename de macros
- `memory/tentativas-frustradas-mts-carrier.md` — Resultados do teste
- `memory/MEMORY.md` — Atualização de status
- `CLAUDE.md` — Atualização de status geral

---

## Comandos de Referência (Teste #1)
```bash
# Setup
cd /mnt/t/downloads/PS4/linux_in_ps4/drivers_mts/build
python3 -m http.server 8888 &

# No PS4 (via SSH/WiFi 192.168.6.128)
wget http://192.168.6.100:8888/mts.ko -O /tmp/mts.ko
rmmod mts
insmod /tmp/mts.ko stage=4

# Verificações
dmesg | tail -50 | grep -i phy
cat /sys/class/net/eth0/carrier
ip link show eth0
```

---

**Status:** ✅ Pronto para Teste #2 quando necessário  
**Documentação:** Completa e atualizada  
**Módulo:** Estável em `drivers_mts/build/mts.ko`
