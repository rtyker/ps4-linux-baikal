---
name: analise-profunda-phy-carrier-2026-07-23
description: Análise profunda do bloqueador de carrier detection no mts.ko
metadata:
  type: project
---

# Análise Profunda: Por que Link Detection não funciona no mts.ko

**Data:** 2026-07-23  
**Foco:** Registrador 0x04 sempre lê link DOWN mesmo com cabo conectado

---

## 1. Sintoma Observado (Teste 3 em tentativas-frustradas-mts-carrier.md)

```
Registrador 0x04 = 0x00000b18

Decodificação:
  bit[0]     = 0  → LINK DOWN (hardware reporta sem link)
  bits[3:2]  = 2  → speed 1000M
  bit[6]     = 0  → half duplex
```

**Esperado:** Com cabo conectado, bit[0] deveria ser 1 (LINK UP).  
**Real:** Sempre 0, independente do cabo estar conectado ou não.

---

## 2. Comparação: Orbis vs. Linux (mts.c atual)

### 2.1 Sequência Orbis (fcn.dc5a31f0 — mts_init)

```c
1. Aloca anéis DMA (TX/RX)
2. Monta descritores 
3. Escreve endereços físicos em BAR0[0x44/0x3c/0x48/0x40]
4. BAR0[0x34] |= 1  // enable MAC core 1
5. BAR0[0x38] |= 1  // enable MAC core 2
6. BAR0[0x54]  = IMR  // máscara de interrupção
7. [depois de if up em SIOCSIFFLAGS]
8. CHAMA: func_0xffffffffdc5a0ba0(softc)  // ← PHY CALIBRATION
```

### 2.2 Sequência mts.c (stage 3+4)

```c
// probe():
- stage >= 2: aloca anéis, programa registradores
- stage >= 3: mts_mac_enable() → escreve BAR0[0x34/0x38]
- stage >= 4: pci_set_master(), request_irq, register_netdev()

// mts_open():
- netif_napi_add() + napi_enable()
- timer_setup() + mod_timer()

// mts_poll() (via timer):
- if mp->enable_carrier: mts_link_check()  // ← LÊ 0x04
```

**DIFERENÇA CRÍTICA:** O driver atual **NUNCA CHAMA A PHY CALIBRATION** (`fc.dc5a0ba0`).

---

## 3. Análise da Função de Calibração PHY (dc5a0ba0)

Entrada: `arg1` = ponteiro do softc  
Saída: configura estado interno do PHY via **operações MDIO** (Clause 45)

### 3.1 Sequência High-Level

```c
// Linhas 35-42: init (enable/disable I/O access)
BAR0[0x200] = 0   // inicializa algo

// Linhas 44-55: configuração de modo
BAR0[0x50] = read(BAR0[0x50])  // lê/reescreve registrador 0x50

// Linhas 56-59: setup de thread/DMA
iVar6 = func_0xffffffffdc73ce90(arg1+0x3090)  // consulta DMA tag
if (iVar6 == 0x200) {
    func_0xffffffffdc73cf90(arg1+0x3090, 0x800)  // setup
}

// Linhas 62-64: MDIO clear
func_0xffffffffdc5a2840(arg1, 2, &var_b0h)  // MDIO devad=2
func_0xffffffffdc5a2840(arg1, 3, &var_b0h)  // MDIO devad=3

// Linhas 65-71: ENABLE
BAR0[0xac] = 9  // ← ATIVAÇÃO DO PHY (devad/endpoint específico)

// Linhas 72+: Loop de calibração MDIO complexo
// Lê vários registradores de BAR2 (glue/pervasive)
// Aplica múltiplos ajustes de impedância/timing via MDIO
// Registradores modificados: 0x12..0x22, 0x37, 0x39, 0x96, 0x107, 0x171..0x175
```

### 3.2 Função `func_0xffffffffdc5a2680/0xffffffffdc5a24d0` — Acesso MDIO

Estes **lêem e escrevem registradores do PHY via transações MDIO Clause 45**.

**Padrão:**
```c
func_0xffffffffdc5a2680(softc, REG_ADDR, &value)   // LÊ
func_0xffffffffdc5a24d0(softc, REG_ADDR, value)    // ESCREVE
```

Os endereços de registrador têm formato `0xDEVAD_REG`:
- `0x12001e` → devad=0x01, reg=0x201e (PCS domain)
- `0x37001e` → devad=0x01, reg=0x371e
- etc.

**Observação:** estas funções usam o **registrador de MDIO da BAR0** (offset 0x00, já documentado no mts.c).

---

## 4. O que está faltando no mts.c

| Passo | Orbis | mts.c | Status |
|-------|-------|-------|--------|
| Aloca anéis DMA | ✅ | ✅ | OK |
| Programa BAR0 registradores | ✅ | ✅ | OK |
| Enable MAC cores 0x34/0x38 | ✅ | ✅ | OK |
| **PHY CALIBRATION (dc5a0ba0)** | ✅ | ❌ | **FALTANDO** |
| Link detection loop | ✅ | ✅ | OK |

---

## 5. Por que o PHY não detecta link

**Hipótese:** O PHY da Baikal (provavelmente um `SFP+`/`RJ45 transceiver` integrado) requer uma **sequência de calibração específica** para entrar em modo operacional. Sem esse setup:

1. O PHY permanece em estado de "reset" ou "low-power"
2. A máquina de estado do link não funciona
3. O registrador 0x04 permanece com bit[0]=0 (link DOWN)

Esta é uma **barreira de software**, não de hardware — o cabo estar conectado é irrelevante se o PHY não está configurado para buscá-lo.

---

## 6. Plano de Ação (Próximo Passo)

### Fase 1: Traduzir dc5a0ba0 para Linux

1. **Decifrar as funções MDIO:**
   - Localizar `func_0xffffffffdc5a2680` (MDIO read) e `func_0xffffffffdc5a24d0` (MDIO write)
   - Verificar se usam o registrador 0x00 (já documentado no mts.c)

2. **Decifrar as leituras de BAR2:**
   - `func_0xffffffffdc7187a0(offset)` → provavelmente lê BAR2+offset
   - Offsets usados: `0x6c`, `0x68`, `0x60`, `0x5c`, `0x100`
   - Estes contêm parâmetros de calibração do glue/SoC

3. **Extrair constantes:**
   - Valores MDIO reais (há muita interpolação/máscara na decompilação)
   - Offsets BAR2 confirmados
   - Sequência exata de leitura/escrita

### Fase 2: Implementar no mts.c

```c
static void mts_phy_calib(struct mts_priv *mp)
{
    // 1. Enable registrador 0xac
    mts_write(mp, 0xac, 9);

    // 2. MDIO clear (devad 2 e 3)
    mts_mdio_read(mp, 2, 0x0000, &dummy);
    mts_mdio_read(mp, 3, 0x0000, &dummy);

    // 3. Loop de calibração (traduzir reads de BAR2 + MDIO writes)
    // ...
}
```

E chamar de `mts_mac_enable()` ou de `mts_open()` após ligar o MAC.

### Fase 3: Testar ao vivo

1. Recompilar mts.ko com PHY calibration
2. Carregar módulo, `ip link set eth0 up`
3. Verificar se `cat /sys/class/net/eth0/carrier` muda para 1
4. Checar se `dmesg` mostra "Link UP"

---

## 7. Referências

- [MTS_INIT_SEQUENCE_dc5a31f0.md](file:///mnt/t/downloads/PS4/linux_in_ps4/consolidado/MTS_INIT_SEQUENCE_dc5a31f0.md) — Sequência de init MAC
- `consolidado/decompiled_dc5a0ba0_gbe_phy_calib.txt` — Decompilação completa da PHY calibration
- [mts.c:379-424](file:///mnt/t/downloads/PS4/linux_in_ps4/drivers_mts/mts.c#L379-424) — `mts_link_check()` atual (só lê, não inicializa)

---

## Resumo Executivo

**Raiz do problema:** O driver Orbis (dc5a0ba0) executa uma **calibração complexa do PHY via MDIO** que o mts.c atual não implementa.  
**Impacto:** Sem essa calibração, o PHY não entra em estado operacional, e a detecção de link falha.  
**Prioridade:** CRÍTICA para alcançar Ethernet funcional.  
**Esforço:** Médio-Alto (decodificar ~150 linhas de assembly/pseudo-C → implementar equivalente em C Linux).
