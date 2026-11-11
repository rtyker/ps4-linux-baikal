# 🔍 Análise Profunda: RX/TX Driver antes de Build (2026-07-23)

**Status:** Investigação de possíveis gargalos antes de compilar  
**Data:** 2026-07-23

---

## 1. Estado do Driver (Verificado)

### ✅ O que Está Implementado

1. **Anéis de DMA:** TX (256 descritores) e RX (256 descritores) alocados corretamente via `dma_alloc_coherent()`
2. **Buffers RX:** 384 KB (256 × 1536 bytes) alocados e mapeados em endereço DMA
3. **Inicialização de Descritores:** 
   - TX: `OWN=1` (livre para driver), `d[2]=0xffff0000`
   - RX: `OWN=0` (esperando hardware), `d[1]=endereço_dma`, `WRAP` no último
4. **Funções de RX/TX:** 
   - `mts_rx_clean()` — processa pacotes com OWN=1, devolve com OWN=0
   - `mts_start_xmit()` — enfileira packet, seta OWN=0 (hardware toma)
   - `mts_tx_reclaim()` — libera skbs quando hardware retorna OWN=1
5. **NAPI:** Configurado via timer de 10ms (não via interrupção — handler está vazio)
6. **Link Detection:** `mts_link_check()` lê STATUS (0x04) e sinaliza carrier up/down

### 🟡 Potenciais Problemas Identificados

#### Problema #1: Ponteiros de Anel Nunca Atualizados
**Localização:** `drivers_mts/mts.c:442-447` (`mts_program_rings()`)

```c
static void mts_program_rings(struct mts_priv *mp)
{
    mts_write(mp, MTS_TX_RING_BASE, lower_32_bits(mp->tx_ring_dma));
    mts_write(mp, MTS_TX_RING_PTR,  lower_32_bits(mp->tx_ring_dma));  // ← ESCRITO UMA VEZ
    mts_write(mp, MTS_RX_RING_BASE, lower_32_bits(mp->rx_ring_dma));
    mts_write(mp, MTS_RX_RING_PTR,  lower_32_bits(mp->rx_ring_dma));  // ← ESCRITO UMA VEZ
}
```

**Questão crítica:** Depois que os buffers são enfileirados/processados, precisa atualizar os ponteiros?

- **TX:** Quando o driver enfileira um novo packet (OWN=0), o hardware precisa saber que há algo novo?
  - Hipótese A: Atualizando 0x3c (TX_RING_PTR) com o endereço do próximo descritor
  - Hipótese B: O hardware varre automaticamente desde BASE até o último descritor
  - Hipótese C: Um registrador de "trigger" ou "start" precisa ser escrito

- **RX:** Quando o driver devolve um buffer (OWN=0), precisa sinalizar?
  - Hipótese A: Atualizando 0x40 (RX_RING_PTR) com o endereço do próximo slot
  - Hipótese B: O hardware lê continuamente todos os descritores com OWN=0
  - Hipótese C: Precisa escrever em registrador de "enable" ou "go"

**Ação recomendada:** Revisar `consolidado/MTS_INIT_SEQUENCE_dc5a31f0.md` ou disassembly do Orbis para ver se há escrita em 0x3c/0x40 dentro de loops.

---

#### Problema #2: Handler de Interrupção Vazio
**Localização:** `drivers_mts/mts.c:1355-1367`

```c
static irqreturn_t mts_interrupt(int irq, void *dev_id)
{
    struct net_device *dev = dev_id;
    struct mts_priv *mp = netdev_priv(dev);
    
    mp->irq_count++;
    return IRQ_HANDLED;  // ← NÃO CHAMA NAPI!
}
```

**Status:** Interrupções não estão conectadas ao NAPI. Polling é feito apenas por timer (10ms).

**Impacto:** Latência de até 10ms entre pacote chegar e ser processado. Não é crítico para conectividade, mas pode causar timeouts se pacotes forem descartados na fila.

**Ação recomendada:** Localizar registrador de **STATUS de interrupção** no RE do Orbis e implementar:
```c
if (status & RX_DONE) napi_schedule();
if (status & TX_DONE) napi_schedule();
```

---

#### Problema #3: Sem Atualização de Ponteiro Tail após Transmissão
**Localização:** `drivers_mts/mts.c:1206-1262` (`mts_start_xmit()`)

```c
static netdev_tx_t mts_start_xmit(struct sk_buff *skb, struct net_device *dev)
{
    // ...
    d[0] = cpu_to_le32(new_ctl);  // ← Descriptor setado
    mp->tx_idx = (idx + 1) & (MTS_RING_SIZE - 1);
    // ...
    return NETDEV_TX_OK;  // ← NUNCA ESCREVE 0x3c AQUI
}
```

**Questão:** O hardware sabe que há um novo packet pronto? Ou precisa ser informado via escrita em 0x3c?

**Teste para validar:**
```bash
# No PS4
ifconfig eth0 up
ping -c 1 192.168.0.1 &
# Olhar para dmesg se há erro de TX timeout
```

Se der timeout, indica que o hardware nunca viu o packet.

---

#### Problema #4: Sem Atualização de Ponteiro Head após Recepção
**Localização:** `drivers_mts/mts.c:1115-1161` (`mts_rx_clean()`)

```c
static int mts_rx_clean(struct mts_priv *mp, int budget)
{
    // ...
    d[0] = cpu_to_le32(new_ctl);  // ← Buffer devolvido ao hardware
    mp->rx_idx = (mp->rx_idx + 1) & (MTS_RING_SIZE - 1);
    // ...
    return cleaned;  // ← NUNCA ESCREVE 0x40 AQUI
}
```

**Questão:** O hardware sabe que há um novo buffer disponível? Ou precisa ser informado via escrita em 0x40?

**Teste para validar:**
```bash
# No PS4, esperar DHCP discover chegando
dhclient eth0
# Ver se eth0 recebe o ARP/DHCP offer
```

Se não receber, pode indicar que o hardware não sabe que há buffers RX prontos.

---

## 2. ✅ RESOLVIDO: Ponteiros de Anel NÃO Precisam ser Atualizados

Conforme **`consolidado/MTS_INIT_SEQUENCE_dc5a31f0.md:99-103`:**
> "escreve-se o mesmo endereço nos dois, e o hardware **avança** o de ponteiro conforme consome descritores"

Medição ao vivo do Orbis:
- `0x44` (TX base): `0x10000000` — **fixo**
- `0x3c` (TX ptr): `0x10000f70` — **avançado pelo hardware**

**✅ Conclusão:** O hardware atualiza automaticamente os ponteiros (0x3c/0x40). Nosso driver está CORRETO ao não atualizá-los.

---

## 3. ❌ PROBLEMA REAL: IMR (0x54) Zerado — Interrupções Desabilitadas

**Descoberta em `consolidado/RE_KERNEL_GBE_ATTACH.md`:**

1. **Registrador 0x54 é definitivamente IMR (Interrupt Mask Register)**
   - Escrito no init: `BAR0[0x54] = sc[0x3098]`
   - Usado para desmascarar: "limpa o bit 12 (`0x1000`)"

2. **Nosso driver:** IMR zerado em 0x00 (todas as interrupções desabilitadas)
   ```c
   #define MTS_IMR_DEFAULT		0x00000000
   ```

3. **Valor correto desconhecido:** `sc[0x3098]` do Orbis não foi documentado
   - Próximo passo: extrair do dump do kernel (`kmem_dump_1252.bin`)
   - OU testar empiricamente (começar com bits 0-15 habilitados, incrementar até funcionar)

**Impacto:** Interrupções nunca disparam. Polling de 10ms compensa, mas é ineficiente.

---

## 4. Checklist Técnico Final (Antes de Build)

### ✅ Verificado e Correto
- [x] Anéis TX/RX alocados e formatados corretamente
- [x] Ponteiros não precisam ser atualizados (hardware faz isso)
- [x] Descritores com flags OWN/WRAP corretas
- [x] RX/TX clean functions implementadas

### ❌ Problemas Identificados
- [ ] **IMR (0x54) zerado** — interrupções desabilitadas
  - Solução: Descubrir valor de `sc[0x3098]` do Orbis
  - Fallback: Testar empiricamente (0x7d, 0xff, 0x1000, etc.)

- [ ] **Handler de IRQ vazio** — não chama NAPI
  - Contorno: Timer de polling (10ms) está funcionando como workaround
  - Solução: Localizar registrador de STATUS para ler flags de RX/TX pronto

### Ações Recomendadas

**Opção 1: Teste com polling (mais rápido)**
1. Compilar com `enable_rx=true` e `enable_tx=true` (já feito ✅)
2. Testar DHCP/ping — se funcionar, problema resolvido
3. Se não funcionar, investigar problema específico

**Opção 2: Reverter IMR para valor padrão Orbis (mais seguro)**
1. Extrair valor de `sc[0x3098]` do `kmem_dump_1252.bin` (offset ~0x3098 na estrutura de softc)
2. Usar esse valor em vez de 0x00
3. Compilar e testar

**Opção 3: Ativar interrupções experimentalmente**
```c
// Em lugar de:
#define MTS_IMR_DEFAULT		0x00000000

// Tentar:
#define MTS_IMR_DEFAULT		0x0000007d  // bits 0-2, 6 habilitados (TX/RX typical)
```

---

## 5. Resumo para Próxima Sessão

| Aspecto | Status | Próximo Passo |
|--------|--------|---------------|
| Alocação de anéis | ✅ OK | Testar ao vivo |
| Formatação de descritores | ✅ OK | Testar ao vivo |
| Atualização de ponteiros | ✅ Hardware faz sozinho | Testar ao vivo |
| Polling NAPI | ✅ Implementado (timer 10ms) | Testar ao vivo |
| IMR (interrupções) | ❌ Zerado, precisa valor | Descubrir ou teste empírico |
| Handler de IRQ | ❌ Vazio, sem NAPI | Localize STATUS register |

**Recomendação:** Compilar agora com as mudanças (enable_rx/tx true) e testar DHCP. Os problemas de IMR/handler de IRQ são OTIMIZAÇÕES, não bloqueadores — polling de 10ms pode funcionar mesmo com IMR zerado (computador processará pacotes 10ms depois de chegarem).

---

## 6. Git Staging

Nenhum commit ainda — essa análise é pré-build. Documente para referência futura.

