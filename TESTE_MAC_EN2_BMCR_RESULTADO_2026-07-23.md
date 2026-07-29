# Teste: Fases 2 e 4 do Plano MAC_EN2 — Resultado

**Data:** 2026-07-23 (noite)
**Mudanças testadas:** log de bisecção pós-calibração (`mts_mac_enable`) +
leitura BMCR via Clause 22 no sysfs `mts_regs`.

## Fase 2 — Bisecção `MTS_MAC_EN2` antes/depois da calibração

```
[pre]        MAC enable:            0x34=0x00000000 0x38=0x00000000 0x50=0x000000a4 0x70=0x00010040
[pos-calib]  MAC enable (pos-calib): 0x34=0x00000000 0x38=0x00000000 0x50=0x00000000 0x70=0x00010040
```

**Conclusão definitiva:** `MTS_MAC_EN2` (0x38) **já nasce em 0 antes da
calibração rodar** — a calibração não é a causa do "zero". O registrador
simplesmente nunca retém o bit de enable, desde a primeira escrita. Mesmo
padrão de "não retenção" do 0x34, contrariando o comentário antigo do código
("escrito 1, lê 8"), que não se reproduz em nenhuma das 3 sessões testadas
até agora nesta rodada de investigação. Fica descartado como causa raiz
provável — mais parece um efeito colateral normal do hardware do que um bug.

## Achado novo e não previsto: `0x50` muda de verdade com o tempo/calibração

```
pre-calib:        0x50 = 0x000000a4
pos-calib:        0x50 = 0x00000000
sysfs (segundos depois, antes do ping): 0x50 = 0x00000004
sysfs (após tentativa de ping):         0x50 = 0x00000004
```

Ao contrário de 0x34/0x38 (sempre zero, estáticos), `0x50` **de fato muda**
ao longo do tempo/estados — é um registrador dinâmico real, não uma trava
morta. Significado ainda não determinado, mas é candidato mais promissor que
0x38 para um indicador real de estado, já que responde a algo (calibração,
possivelmente transições de link).

## Fase 4 — BMCR via Clause 22 (phy_addr=0x00, reg=0x00)

```
BMCR (C22 phy=0x00, reg=0x00): timeout (ret=-110)
```

**Confirma o resultado já visto no diagnóstico antigo** (`mts_mdio_probe`,
sessão anterior: "Clause 22: ret=-110") — Clause 22 com `phy_addr=0x00`
simplesmente não responde, timeout limpo, sem crash. Não deu nenhum sinal
novo do PHY.

## Fase B (duplex, revisão) — reconfirmado sem mudança

Todos os registradores Clause 45 (PMA/PMD Control1/Status1/ID1/ID2, AN
Status, 1000BASE-T AN Status) continuam em `0x0000`, `ret=0` (sem timeout).
`Link change: 1000 Mbps Half duplex` continua idêntico. `MTS_CNT_PKTS=0`,
ping direto `192.168.0.1↔192.168.0.2` continua 100% de perda nos dois
sentidos.

## Confirmação adicional da Fase A (throttling)

dmesg mostrou resíduo de uma sessão anterior bem mais longa (contador
`rx_debug_logs` chegando a 38000, uma entrada a cada 1000 exatamente como
esperado, ao longo de ~2000s de uptime) antes do reload atual reiniciar o
contador do zero. Confirma que o throttling funciona de forma estável em
janelas longas, não só nos primeiros segundos.

## Conclusão consolidada desta rodada

1. **`MTS_MAC_EN2` não é mais suspeito de causa raiz** — comportamento
   consistente de "não retenção" em 3 sessões, não é regressão nem efeito de
   calibração.
2. **`0x50` é a única pista nova e genuinamente dinâmica** encontrada hoje —
   muda de valor de forma correlacionada com calibração/tempo, ao contrário
   de tudo mais testado. Significado ainda desconhecido.
3. **Clause 22 (BMCR) e Clause 45 (PMA/PMD, AN Status) não dão nenhum sinal
   do PHY**, nem durante calibração nem minutos depois do "Link change"
   aparecer — reforça a hipótese de que o PHY nunca sai de um estado
   efetivamente não-responsivo via MDIO, independente do que o registrador
   de status do MAC (`0x04`) relata.
4. **Nenhum progresso em conectividade real**: `MTS_CNT_PKTS=0`, ping 100%
   perda, igual às sessões anteriores.

## Próximos passos possíveis (não iniciados, aguardando decisão do usuário)

- Varrer `phy_addr` de 0 a 31 no Clause 22 (hoje só testado com `phy_addr=0`)
  — o endereço real do PHY pode não ser 0.
- Investigar o significado de `0x50` mais a fundo — talvez sondando-o em
  mais pontos ao longo da calibração (não só antes/depois inteiro).
- Considerar que a sequência de wakeup do PHY (glue + MDIO, já
  extensivamente reverse-engenheirada em sessões anteriores) pode ter um
  passo faltante — mas isso é um projeto de RE maior, fora do escopo das
  fases testadas até aqui.
