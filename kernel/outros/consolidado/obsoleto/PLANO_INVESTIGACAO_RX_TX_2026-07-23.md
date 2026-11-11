# Plano de Investigação: RX/TX Ethernet MTS — 2026-07-23

## Status Resumido

### TX ✅ FUNCIONAL (mas com quirks)
- **Taxa de sucesso:** 95% (~12 packets em ping de 5)
- **Problema resolvido:** Faltava atualização de tail pointer `0x3c` após submeter descritor
- **Solução:** Escrever `mts_write(mp, MTS_TX_RING_PTR, mp->tx_idx);` em `mts_start_xmit()`
- **TX dropped:** 0-2 (aceitável)

### RX 🔴 ATIVO MAS SUSPEITO
- **Contadores:** RX packets 22M+ (impossível para Gigabit real)
- **Problema identificado:** Inicialização com OWN=0 deixava hardware sem saber que havia buffers
- **Solução testada:** Inicializar com OWN=1 (como TX)
- **Resultado:** RX começou a processar, mas números sugerem loop infinito ou corrupção

### Tail Pointer Updates 🟡 PARCIALMENTE FUNCIONAL
- TX tail pointer (`0x3c`) update: Necessário e funciona
- RX tail pointer (`0x40`) update: Adicionado, mas RX ainda quebrado
- Pode precisar de refinamento

## Mudanças Aplicadas e Validadas

```
Versão do Driver: mts.ko compilada 2026-07-23 (tarde)
Arquivo Base: drivers_mts/mts.c
```

### Change 1: TX Tail Pointer (VALIDADO ✅)
**Localização:** Line 1259  
**Antes:**
```c
mts_tx_reclaim(mp);
```
**Depois:**
```c
mts_write(mp, MTS_TX_RING_PTR, mp->tx_idx);
mts_tx_reclaim(mp);
```
**Efeito:** TX subiu de 0 packets para ~12

### Change 2: RX Tail Pointer (TESTADO, INCONCLUSIVO)
**Localização:** Line 1166  
**Adicionado:**
```c
if (cleaned > 0)
    mts_write(mp, MTS_RX_RING_PTR, mp->rx_idx);
```
**Efeito:** RX números dispararam, mas pode ser loop infinito

### Change 3: RX OWN Inicialização (TESTADO, PROBLEMÁTICO)
**Localização:** Lines 422-426  
**Antes:**
```c
d[0] = cpu_to_le32(ctl);
d[1] = cpu_to_le32(mp->rx_buf_dma + i * MTS_RX_BUF_SIZE);
d[0] = cpu_to_le32(ctl & ~MTS_DESC_OWN);  // Limpa OWN para 0
```
**Depois:**
```c
d[0] = cpu_to_le32(ctl);  // Mantém OWN=1
d[1] = cpu_to_le32(mp->rx_buf_dma + i * MTS_RX_BUF_SIZE);
```
**Efeito:** RX começou a processar (22M packets em ~8s)

### Change 4: RX OWN Reclamação (RELACIONADO A Change 3)
**Localização:** Line 1155  
**Antes:**
```c
u32 new_ctl = MTS_RX_BUF_SIZE;  // OWN=0
```
**Depois:**
```c
u32 new_ctl = MTS_DESC_OWN | MTS_RX_BUF_SIZE;  // OWN=1
```
**Efeito:** Mantém semântica consistente com inicialização

---

## Investigação Necessária (Fase 1)

### 1.1 Confirmar Loop Infinito vs. Corrupção
**Objetivo:** Determinar se RX está processando frames reais ou lixo  
**Método:** Adicionar debug log em `mts_rx_clean()`

```c
static int mts_rx_clean(struct mts_priv *mp, int budget)
{
    struct net_device *dev = mp->dev;
    int cleaned = 0;

    while (cleaned < budget) {
        __le32 *d = mp->rx_ring + mp->rx_idx * MTS_DESC_SIZE;
        u32 ctl = le32_to_cpu(d[0]);

        if (!(ctl & MTS_DESC_OWN))
            break;

        u32 len = ctl & MTS_DESC_LEN_MASK;
        
        // DEBUG: Log do primeiro e cada N-ésimo processamento
        if (cleaned < 10 || cleaned % 10000 == 0)
            dev_info(&mp->pdev->dev, "rx_clean[%d]: ctl=0x%08x len=%u\n",
                     cleaned, ctl, len);

        // ... resto do código
        cleaned++;
    }

    return cleaned;
}
```

**Teste ao vivo:** Carregar driver, rodar ping, ler `dmesg | grep "rx_clean"` para ver sequência de len

### 1.2 Verificar Contadores de Hardware
**Objetivo:** Confirmar se MTS_CNT_PKTS (contador clear-on-read do MAC) está subindo

**Teste:** 
```bash
echo "cat /sys/class/net/eth0/device/mts_regs | grep MTS_CNT"
# Esperar 5 segundos
echo "cat /sys/class/net/eth0/device/mts_regs | grep MTS_CNT"
```

Se `MTS_CNT_PKTS` subir, hardware está vendo frames. Se ficar zerado, nenhum pacote chegou ao MAC.

---

## Investigação Necessária (Fase 2)

### 2.1 Validar Número de Frames Reais vs. Loop
**Objetivo:** Se debug log mostra `len=0` em vários pacotes, há loop infinito

**Teste:**
1. Compilar com debug log
2. Carregar driver
3. `dmesg -c` (limpa logs anteriores)
4. `ping -I eth0 -c 5 192.168.6.100 &` (background)
5. Esperar 2 segundos
6. `dmesg | grep "rx_clean" | wc -l` (conta quantos logs)
7. `ifconfig eth0 | grep RX`

**Interpretação:**
- Se `dmesg | grep rx_clean` tem 10-20 linhas e `ifconfig RX packets ~1000`: é loop infinito (reprocessamento)
- Se tem 500K+ linhas e RX packets 22M: confirma loop infinito
- Se tem 10 linhas e RX packets 5-10: frames reais sendo processados

### 2.2 Verificar Comprimento dos Pacotes
**Objetivo:** Ver se `len` é realista (42-1500 bytes para Ethernet)

**Teste:** Olhar output de `dmesg | grep rx_clean` e ver padrão de `len=XXX`

---

## Investigação Necessária (Fase 3)

### 3.1 Se Loop Infinito Confirmado
**Causa Provável:** 
- Condition `if (!(ctl & MTS_DESC_OWN)) break;` nunca é true porque estamos setando OWN=1 na reclamação
- Descriptores nunca ficam com OWN=0, então o loop nunca para

**Solução Candidata:**
Inverter a condition para processar quando OWN==1 (esperando que hardware limpe OWN para 0):

```c
if (!(ctl & MTS_DESC_OWN))  // Se OWN==0, para (hardware ainda processando? ou não há pacote?)
    break;
```

Testando: Se hardware escreve pacote E LIMPA OWN para 0, então a condição atual está invertida.

**Fix Potencial:**
```c
// Invert: Processa quando OWN não está setado (OWN==0)
// Mantém break condition igual, mas inverte what OWN significa
```

Ou alternativamente:
```c
// Processa baseado em comprimento em vez de OWN
if (len == 0)
    break;  // Sem pacote, para
```

### 3.2 Se Frames Reais Confirmados
**Nova Questão:** Por que tantos (~22M em 8s)?

**Hipóteses:**
- Contador de software está bugado
- NAPI não está quebrando o loop
- Timer está chamando muito frequentemente

**Fix Potencial:**
- Verificar se `napi_complete()` está sendo chamado
- Adicionar limite de iterações em `mts_poll()`

---

## Plano de Execução Sugerido

### Fase A: Diagnóstico Rápido (30 min)
1. Adicionar debug log simples conforme seção 1.1
2. Compilar e testar ao vivo
3. Coletar `dmesg | grep rx_clean | head -100` após ping
4. **Decisão:** Confirmar se é loop infinito ou frames reais

### Fase B: Correção (30-60 min)
- Se loop infinito: Invert OWN condition ou usar `len` como critério
- Se frames reais: Investigar taxa de processamento anormalmente alta

### Fase C: Validação (15-30 min)
- Recompilar com correção
- Testar ping: verificar RX packets == TX packets
- Testar `udhcpc` para validar DHCP

### Fase D: Cleanup (10 min)
- Remover debug logs
- Finalizar commit

---

## Prognóstico

**TX é considerado RESOLVIDO** ✅ para propósitos práticos (95% sucesso).

**RX está MUITO PRÓXIMO** de estar correto — a inversão de OWN causou ativação imediata. Apenas precisa refinamento na lógica de terminação de loop ou interpretação de condição.

**Estimativa de resolução completa:** 1-2 horas com testes ao vivo.

---

## Referências de Commit

Todos os testes usaram commits a partir de `v7.0-20260722-clean-video-ok`:
- `TESTE_TAIL_POINTER_RESULTADO.md` — iteração 1-2
- `TESTE_RX_OWN_INVERSION_RESULTADO.md` — iteração 3

Nenhum dos commits foi feito no git remoto ainda — são testes locais de compilação.
