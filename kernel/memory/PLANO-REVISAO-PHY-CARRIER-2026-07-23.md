---
name: plano-revisao-phy-carrier-completo
description: Plano completo de análise + implementação para PHY carrier detection
metadata:
  type: project
---

# 🎯 PLANO COMPLETO — PHY Carrier Detection no mts.ko
**Criado:** 2026-07-23  
**Status:** Pronto para Revisão  
**Prioridade:** CRÍTICA (bloqueador de Ethernet funcional)

---

## 📊 RESUMO EXECUTIVO

### Problema
- Registrador 0x04 sempre lê link DOWN (`0x00000b18`, bit[0]=0)
- Esperado: Com cabo conectado, bit[0] deveria ser 1
- **Causa raiz:** Driver Orbis executa calibração PHY (função `dc5a0ba0`) que mts.c não implementa

### Solução
Traduzir e implementar a rotina de calibração PHY do Orbis no `mts.c`:
- ~200 linhas de assembly/pseudo-C
- 15+ registradores MDIO para escrever
- Leitura de 5 parâmetros de BAR2 (glue)

### Impacto
- ✅ Link detection funciona
- ✅ Carrier ON/OFF correto
- ✅ DHCP e tráfego de rede possíveis

---

## 🔍 ANÁLISE TÉCNICA

### 1. Comparação: Orbis vs Linux

#### Orbis (kernel 12.52)
```
mts_init() [fcn.dc5a31f0]
├─ Aloca anéis DMA ............................ ✅ mts.c implementa
├─ Monta descritores TX/RX ................... ✅ mts.c implementa
├─ Programa BAR0[0x44/0x3c/0x48/0x40] ....... ✅ mts.c implementa
├─ Enable MAC cores BAR0[0x34/0x38] ......... ✅ mts.c implementa
├─ Write IMR BAR0[0x54] ...................... ✅ mts.c implementa
└─ PHY CALIBRATION [fcn.dc5a0ba0] ........... ❌ mts.c NÃO IMPLEMENTA
   └─ BAR0 writes (0x200, 0xac)
   └─ MDIO clear (devad 2, 3)
   └─ MDIO calib loop (15+ writes)
   └─ BAR2 parameter reads (5 offsets)
```

#### Linux (mts.c atual)
```
mts_probe() [stage 2+]
├─ Aloca e configura anéis DMA .............. ✅
├─ Escreve BAR0 registradores ............... ✅
└─ mts_mac_enable() .......................... ✅

mts_open()
├─ NAPI + timer setup ....................... ✅
└─ mts_link_check() .......................... ✅ (mas falha porque PHY não está calibrado)
```

**DIFERENÇA CRÍTICA:** Falta a chamada a `mts_phy_calib()` equivalente a `dc5a0ba0`.

---

### 2. Sequência de Calibração PHY (dc5a0ba0)

#### Fase 1: Init (4 operações)
```c
BAR0[0x200] = 0                    // Desabilita I/O
val = BAR0[0x50]; BAR0[0x50] = val // Lê-escreve (confirma estado)
MDIO_read(devad=2, reg=0x0000)     // Clear 1
MDIO_read(devad=3, reg=0x0000)     // Clear 2
```

#### Fase 2: Enable (1 operação)
```c
BAR0[0xac] = 9  // ← Ativação do PHY
```

#### Fase 3: Calibração MDIO (15+ operações com lógica complexa)

**Padrão geral:**
```c
for (cada grupo de calibração) {
    u32 param_i = BAR2[offset_i];           // Lê parâmetro BAR2
    u32 calib_val = EXTRACT_BITS(param_i);  // Extrai/interpola bits
    MDIO_write(devad, reg, calib_val);      // Escreve no PHY
}
```

**Offsets BAR2 utilizados:**
- `0x6c`, `0x68`, `0x60`, `0x5c`, `0x100`

**Registradores MDIO (formato 0xDDRRRR onde DD=devad, RRRR=reg):**
```
devad=0x01:
  0x201e, 0x211f, 0x161e, 0x171e, 0x181e, 0x191e
  0x201e, 0x211f, 0x161e, 0x171e, 0x181e, 0x191e
  0x207e, 0x217e, 0x267e, 0x277e, 0x291e, 0x2a1e
  
devad=0x01 (extended):
  0x371e, 0x391e, 0x961e, 0x1071f, 0x1711e, 0x1721e, 0x1731e
```

---

### 3. Offsets BAR2 e Significado

| Offset | Esperado | Significado |
|--------|----------|------------|
| `0x6c` | ? | Parâmetro de calibração 1 |
| `0x68` | ? | Parâmetro de calibração 2 |
| `0x60` | ? | Parâmetro de calibração 3 |
| `0x5c` | ? | Parâmetro de calibração 4 |
| `0x100` | ? | Parâmetro de calibração 5 |

**⚠️ Estes precisam ser validados ao vivo.**

---

## 📋 PLANO DE IMPLEMENTAÇÃO

### Fase 0: Validação Pré-Implementação ⭐ RECOMENDADO

**Objetivo:** Confirmar que offsets BAR2 são seguros de ler.

```bash
# Via netconsole/telnet no PS4 com kernel rodando

# 1. Verificar que BAR2 está mapeada
cat /proc/iomem | grep -i "pervasive\|glue\|baikal"

# 2. Ler offsets BAR2 (read-only, seguro)
# BAR2_VA é o endereço virtual mapeado (provável: 0xffffffffde000000+)
# BAR2_PA é o endereço físico (provável: 0xc8800000)

dd if=/dev/mem bs=4 count=1 skip=$((0xc8800000/4 + 0x6c/4)) 2>/dev/null | od -An -tx4
dd if=/dev/mem bs=4 count=1 skip=$((0xc8800000/4 + 0x68/4)) 2>/dev/null | od -An -tx4
dd if=/dev/mem bs=4 count=1 skip=$((0xc8800000/4 + 0x60/4)) 2>/dev/null | od -An -tx4
dd if=/dev/mem bs=4 count=1 skip=$((0xc8800000/4 + 0x5c/4)) 2>/dev/null | od -An -tx4
dd if=/dev/mem bs=4 count=1 skip=$((0xc8800000/4 + 0x100/4)) 2>/dev/null | od -An -tx4

# 3. Verificar que os valores retornam consistentemente (não aleatórios)
# Se retornar algo != 0 = offset é válido
```

**Saída esperada:** Confirmação que cada offset lê um valor válido (não aleatório).

---

### Fase 1: Implementação Versão Minimal

**Objetivo:** Testar se a calibração básica já melhora o carrier detection.

**Arquivo:** Criar `drivers_mts/mts_phy_calib.c` ou adicionar em `mts.c`

```c
static void mts_phy_calib_minimal(struct mts_priv *mp)
{
    // Fase 1: Init
    mts_write(mp, 0x200, 0);
    uint32_t val = mts_read(mp, 0x50);
    mts_write(mp, 0x50, val);
    
    // MDIO clear
    uint16_t dummy;
    mts_mdio_read(mp, 2, 0x0000, &dummy);
    mts_mdio_read(mp, 3, 0x0000, &dummy);
    
    // Fase 2: Enable PHY
    mts_write(mp, 0xac, 9);
    
    dev_info(&mp->pdev->dev, "PHY calibration minimal: OK\n");
}
```

**Chamada:** Em `mts_mac_enable()` ou `mts_open()` (após enable MAC cores).

**Teste ao vivo:**
```bash
# Carregar módulo
insmod mts.ko stage=4

# Observar dmesg
dmesg | grep "PHY calibration"

# Verificar carrier
cat /sys/class/net/eth0/carrier
```

**Esperado se funcionar:** carrier = 1 (ou mensagem "Link UP" no dmesg)

---

### Fase 2: Implementação Completa

**Objetivo:** Implementar loop de calibração MDIO completo.

**Entrada:** `consolidado/decompiled_dc5a0ba0_gbe_phy_calib.txt` (200 linhas)

**Processo:**
1. Transcrever cada leitura BAR2 + escrita MDIO
2. Substituir nomes de funções:
   - `func_0xffffffffdc7187a0(offset)` → `gbe_calib_read(offset)` → `*(BAR2 + offset)`
   - `func_0xffffffffdc5a2680/24d0(...)` → `mts_mdio_read/write(...)`
3. Manter sequência exata de operações

**Código skeleton:**
```c
static void mts_phy_calibration_full(struct mts_priv *mp)
{
    // Fase 1: Init (igual à minimal)
    mts_write(mp, 0x200, 0);
    uint32_t val = mts_read(mp, 0x50);
    mts_write(mp, 0x50, val);
    
    uint16_t dummy;
    mts_mdio_read(mp, 2, 0x0000, &dummy);
    mts_mdio_read(mp, 3, 0x0000, &dummy);
    
    // Fase 2: Enable
    mts_write(mp, 0xac, 9);
    
    // Fase 3: Calibração MDIO (15+ grupos)
    // Grupo 1: Lê 0x6c, calcula, escreve
    uint32_t p0 = gbe_calib_read(mp, 0x6c);
    if ((p0 & 0x80800000) == 0x80800000) {
        uint32_t p1 = gbe_calib_read(mp, 0x68);
        uint32_t field = (p1 & 0x3f) << 8;
        mts_mdio_write(mp, 0x01, 0x201e, field);
        
        // ... (próximos grupos, mesmo padrão)
    }
}

// Helper: lê valor de BAR2
static uint32_t gbe_calib_read(struct mts_priv *mp, uint32_t offset)
{
    // TODO: confirmar endereço BAR2
    // Provável: BAR2_VA + offset
    return ioread32(???);  
}
```

**Custo:** ~300 linhas de código, 2-3h de trabalho.

---

### Fase 3: Validação e Teste

**Checklist:**
- [ ] Código compila sem erro
- [ ] Módulo carrega com `insmod mts.ko stage=4`
- [ ] Não há Kernel Panic ou Oops
- [ ] `dmesg` mostra "PHY calibration: OK"
- [ ] `cat /sys/class/net/eth0/carrier` retorna 1
- [ ] `ip link show eth0` mostra "UP, BROADCAST, RUNNING"
- [ ] `dmesg` mostra "Link UP" após `ip link set eth0 up`

---

## 🚀 ESTRATÉGIA RECOMENDADA

### Opção A: Incremental (SAFEST)
1. ✅ Fase 0: Validar offsets BAR2 (30 min)
2. ✅ Fase 1: Implementar minimal (1h)
3. ⏳ Testar ao vivo (30 min)
4. ✅ Fase 2: Se minimal funcionar → completar (2h)

**Total:** ~4h, risco mínimo

### Opção B: Full Direct (FASTER)
1. ✅ Validar offsets BAR2 (30 min)
2. ✅ Transcrever completo (2h)
3. ⏳ Testar ao vivo (30 min)

**Total:** ~3h, risco: interpretação errada de um registrador

---

## 📌 RISCOS E MITIGAÇÕES

| Risco | Prob | Severidade | Mitigation |
|-------|------|-----------|-----------|
| Offset BAR2 diferente em Baikal | Baixa | Alta | Validar ao vivo antes (Fase 0) |
| DEVAD/reg MDIO errado | Baixa | Baixa | MDIO write não causa crash |
| Ordem operações importa | Média | Média | Respeitar sequência exata (easy) |
| PHY já está calibrado | Baixa | Nenhuma | Operação idempotente |
| Registrador 0xac faz algo perigoso | Muito Baixa | Média | Pesquisar antes de escrever |

---

## 📚 REFERÊNCIAS

Documentos na pasta `memory/`:
- `analise-profunda-phy-carrier-2026-07-23.md` — Detalhe técnico
- `plano-implementacao-phy-calib-2026-07-23.md` — Pseudocódigo
- `tentativas-frustradas-mts-carrier.md` — Histórico de testes

Documentos em `consolidado/`:
- `MTS_INIT_SEQUENCE_dc5a31f0.md` — Sequência completa Orbis
- `decompiled_dc5a0ba0_gbe_phy_calib.txt` — Decompilação pseudocódigo (fonte primária)
- `RE_KERNEL_GBE_ATTACH.md` — Análise de offsets BAR2

---

## ✅ PRÓXIMAS AÇÕES (SUA DECISÃO)

**Opção 1:** Começar Fase 0 (validação BAR2 ao vivo)  
**Opção 2:** Pular Fase 0, confiar em análise estática (risco: médio)  
**Opção 3:** Aguardar revisão mais profunda  
**Opção 4:** Algo diferente?

---

## 📝 Checklist de Revisão

- [ ] Entendi a causa raiz (falta PHY calib)
- [ ] Entendi a estratégia (Fase 0/1/2/3)
- [ ] Achei uma opção viável
- [ ] Tenho dúvidas (favor especificar)

---

**Documentação:** ✅ Completa  
**Status:** Aguardando sua revisão e decisão  
**Pronto para:** Fase 0 (validação) ou Fase 1 (implementação minimal)
