---
name: glue-ack-lock-global-divergencia-orbis-2026-07-28
description: O par write/read do ACK do glue precisa de lock GLOBAL como no Orbis — nosso código usa lock por descritor
metadata:
  type: project
---

**Divergência confirmada com o Orbis** (RE de `dc718b40`, já no corpus decompilado,
catalogada em `decompiled_functions`).

O registrador `0x110084` (`BPCIE_ACK_WRITE`) é um **seletor compartilhado** entre a
func 4 (`icc`), a func 5 (DMAC) e a func 7 (xHCI + AHCI interno). O acesso é um par
não-atômico: escreve-se qual grupo se quer, depois lê-se `0x110088`
(`BPCIE_ACK_READ`) para obter a máscara de subfunções pendentes.

**Orbis serializa esse par com um mutex GLOBAL único** (objeto `0xffffffffde615a80`;
lock em `dc6c8710` linha 318, unlock em `dc6c88b0` linha 321):

```
lock(global) -> write(0x110084, seletor) -> read(0x110088) -> unlock(global)
```

**Nosso `bpcie_handle_edge_irq()` usa `raw_spin_lock(&desc->lock)`** — lock *por
descritor*, que não dá exclusão mútua entre descritores diferentes. Dois handlers em
CPUs distintas podem interleavar: um escreve o seletor, o outro escreve por cima, e o
primeiro lê a máscara do grupo errado.

**Why:** é bug de concorrência real e divergência clara do comportamento de
referência. **Mas provavelmente NÃO é a causa da falha do SATA** — se a corrida fosse
frequente veríamos invocações com máscara zerada (`VAZIO`), e a instrumentação mediu
**zero**; além disso o `icc`, principal candidato a colidir, disparou só 26 vezes no
boot inteiro. Corrigir mesmo assim, por ser bug legítimo.

**How to apply:** trocar o `raw_spin_lock(&desc->lock)` por um spinlock global do
driver, cobrindo apenas o par write/read. Confirmações úteis vindas do mesmo RE: os
valores mágicos do nosso demux **estão corretos** (func 4 → w=2/mask=-1/shift=0;
func 7 → w=3/mask=7/shift=0x10; func 5 → w=3/mask=3/shift=0), e o cálculo
`mask & ~(valor >> shift)` bate com o `andn` do Orbis. Diferença estrutural: a função
do Orbis só **devolve** a máscara, o dispatch fica no chamador; a nossa faz as duas
coisas. O corpus decompilado **não tem nada de AHCI/SATA no lado da interrupção** —
a resposta para "por que o glue deixa de sinalizar a subfunção 1" não está lá.
Relacionado: [[baikal-func7-um-unico-vetor-msi-2026-07-28]].
