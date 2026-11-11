# TESTE: Inversão OWN em RX — Resultado Importante

**Data:** 2026-07-23 (tarde)  
**Kernel:** v7.0-20260722-clean-video-ok  
**Driver:** `mts.ko` stage=4 com TX tail pointer fix + RX tail pointer update  

## Mudanças Aplicadas

1. **TX tail pointer update** (linha 1259):
   ```c
   mts_write(mp, MTS_TX_RING_PTR, mp->tx_idx);
   ```

2. **RX tail pointer update** (linha 1166):
   ```c
   if (cleaned > 0)
       mts_write(mp, MTS_RX_RING_PTR, mp->rx_idx);
   ```

3. **RX inicialização com OWN=1** (linha 422):
   ```c
   d[0] = cpu_to_le32(ctl);  // ctl com MTS_DESC_OWN setado
   // Removido: d[0] = cpu_to_le32(ctl & ~MTS_DESC_OWN);
   ```

4. **RX reclaim restaura com OWN=1** (linha 1155):
   ```c
   u32 new_ctl = MTS_DESC_OWN | MTS_RX_BUF_SIZE;
   ```

## Resultado Inesperado

**Antes (RX inicializado com OWN=0):**
- RX packets: 0
- RX bytes: 0

**Depois (RX inicializado com OWN=1):**
- RX packets: **22,372,508** ✅ (interface ativa!)
- RX bytes: 34,364,172,288 (34 GB) ⚠️ (suspeito)
- TX packets: 12 (normal)
- TX dropped: 0 (melhorou!)

## Análise do Resultado

### Positivo ✅
- **RX agora está processando descritores** — mudança de OWN=1 na init fez diferença crítica
- TX dropped caiu de 2 para 0
- Contador de RX não está mais zerado — hardware está comunicando algo

### Preocupante ⚠️
- **Números absurdos**: 22 milhões de pacotes em um ping de ~5-10 segundos
- Taxa de 22M pacotes / 8 segundos = 2.75 milhões por segundo (impossível para Gigabit Ethernet físico)
- Bytes: 34 GB indicam lixo/corrução, não frames Ethernet reais (máx esperado: ~12 KB para ping)
- Provável diagnóstico: **Driver está em loop infinito processando descritores**, ou o contador está corrompido

## Hipóteses de Próximo Passo

1. **Loop infinito de RX**: `mts_rx_clean()` nunca para porque OWN está sempre setado para 1 na reclamação
   - Solução: Adicionar condição de parada ou limite de iteração
   
2. **Memória corrompida**: O padrão OWN=1 que esperamos não é exatamente MTS_DESC_OWN
   - Verificar se MTS_DESC_OWN está definido como BIT(31) correto

3. **Descritor RX não é processado como esperado**: O hardware não reconhece OWN=1 como "buffer vazio"
   - Pode ser que RX use semântica de OWN completamente inversa ao TX

## Próxima Ação Recomendada

Adicionar **log de debug** em `mts_rx_clean()` para ver:
1. Quantas iterações o loop faz antes de quebrar
2. Qual é o valor de ctl nos primeiros descritores processados
3. Se `len` (comprimento do pacote) é realista ou lixo

Exemplo debug:
```c
dev_info(&mp->pdev->dev, "rx_clean: processed idx=%d ctl=0x%x len=%u cleaned=%d\n",
         mp->rx_idx, ctl, len, cleaned);
```

Isso vai ajudar a entender se está processando frames reais ou lixo.

## Commits Relacionados

Todos no arquivo `drivers_mts/mts.c`:
- Linha 422: Removida limpeza de OWN em inicialização RX
- Linha 1155-1157: Mudado restauração para `MTS_DESC_OWN | MTS_RX_BUF_SIZE`
- Linha 1166-1168: Adicionado tail pointer update para RX

## Conclusão Atual

**Semântica de OWN está invertida entre TX e RX!**
- TX: OWN=1 significa "vazio, software pode escrever"
- RX: OWN=1 significa "vazio, hardware pode receber"

Mas o comportamento de loop infinito sugere que há mais uma inversão em algum lugar (talvez na condição de processamento). Próximo passo é instrumentar com debug logs.
