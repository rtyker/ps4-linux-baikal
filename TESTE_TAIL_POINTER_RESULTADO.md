# TESTE: Correção do Tail Pointer TX — Resultado

**Data:** 2026-07-23  
**Kernel:** v7.0-20260722-clean-video-ok (baseline estável)  
**Driver:** `mts.ko` stage=4 com atributo sysfs `mts_regs`  
**Alteração testada:** Escrita de tail pointer `0x3c` após submeter novo descritor TX

## Problema Identificado

O driver `mts_start_xmit()` **não atualizava o registrador de tail pointer TX (`0x3c`)**  após submeter um novo descritor. O hardware **não receber aviso** de que há novo descritor para processar.

## Teste 1: Tail Pointer = Endereço (base + offset em bytes)

```c
mts_write(mp, MTS_TX_RING_PTR, lower_32_bits(mp->tx_ring_dma + mp->tx_idx * 16));
```

**Resultado:**
- TX packets: 0
- TX dropped: 6
- **Análise:** Mínima melhora (queda de 12-20 para 6 drops), mas TX não funcionou

## Teste 2: Tail Pointer = Índice do Descritor (0-255)

```c
mts_write(mp, MTS_TX_RING_PTR, mp->tx_idx);
```

**Resultado:**
- TX packets: **19** ✅
- TX dropped: **2** ✅
- TX bytes: 1146
- tx_idx: 20, tx_clean: 20 (sincronizados)
- Descritores TX: Todos com OWN=1 (liberados, reutilizáveis)
- Hexdump: Mostra dados de pacotes nos buffers TX

**Conclusão:** ✅ **TX FUNCIONANDO!** Apenas 2 drops em ~21 tentativas (~95% sucesso)

## Problema Remanescente: RX Zerado

Apesar de TX agora funcionar, **RX não está recebendo nada**:
- RX packets: 0
- RX bytes: 0
- rx_idx: 0 (nunca avançou)
- MTS_CNT_PKTS (hardware counter): 0
- RX buffers: Todos com zeros (hexdump 00 00 00...)

### Hipóteses

1. **Host não está respondendo** — Mas ping foi executado 5x e nenhuma resposta foi recebida
2. **RX inicialização invertida** — Inicializa com OWN=0 em todos descritores (diferente de TX que começa OWN=1)
3. **RX tail pointer também precisa de atualização** — Análogo ao TX (mas RX estava funcionando antes com 49 pacotes)
4. **MAC RX não está habilitado** — Registrador 0x38 mostra 0x08 (enable bit deve estar aí?)

## Estado do Hardware

```
Link Status: 0x00000b19 → 1000 Mbps, Half-duplex, Link UP
MAC Enable (0x38): 0x00000008 (parece habilitado?)
IMR (0x54): 0x00000000 (todas interrupções mascaradas)
tx_idx: 20, tx_clean: 20 (TX sincronizado)
rx_idx: 0 (não avançou)
```

## Próximas Investigações

1. **Verificar se RX também precisa de tail pointer update** — Similar ao TX, depois de mts_rx_clean() reliberar buffers
2. **Investigar semântica de inicialização RX** — Por que OWN=0 na init, ao contrário de TX?
3. **Testar se hardware realmente está recebendo frames** — Usar analisador rede ou monitor MMIO
4. **Verificar MAC RX enable** — Pode ser que o MAC RX não tenha sido ativado (0x38/0x50 podem ter significado diferente)

## Mudanças Commitadas

Arquivo: `drivers_mts/mts.c` linha 1259:

**Antes:**
```c
/* tenta reclamar TX completos de forma oportunista */
mts_tx_reclaim(mp);
```

**Depois:**
```c
/* avisa o hardware: novo descritor pronto (tail pointer = índice) */
mts_write(mp, MTS_TX_RING_PTR, mp->tx_idx);

/* tenta reclamar TX completos de forma oportunista */
mts_tx_reclaim(mp);
```

## Conclusão Atual

✅ **TX RESOLVIDO** com tail pointer = índice  
❌ **RX AINDA QUEBRADO** - próxima investigação necessária

Estimativa de investigação RX: Verificar se padrão é idêntico ao TX (tail pointer + inicialização OWN invertida).
