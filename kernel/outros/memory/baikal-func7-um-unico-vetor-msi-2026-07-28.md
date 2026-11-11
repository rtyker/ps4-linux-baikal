---
name: baikal-func7-um-unico-vetor-msi-2026-07-28
description: O hardware Baikal agrega todas as IRQs da função 7 num único vetor MSI — alocar múltiplos vetores é inútil
metadata:
  type: project
---

**MEDIDO AO VIVO 2026-07-28 com instrumentação no demux.** A função 7 do Baikal
(`0000:00:14.7` — dois xHCI + o AHCI do HD interno) **agrega todas as suas
interrupções numa única mensagem MSI**, a da subfunção 0 (hwirq `0x14e0` = 5344).

```
chamadas no vetor f7 sub0 (hwirq 0x14e0):  4096+
chamadas no vetor f7 sub1 (hwirq 0x14e1):     0   <- "dedicado" ao AHCI, NUNCA dispara
invocações do demux sem nada a despachar:     0
```

Todas as entregas ao AHCI vieram com `origem sub0`. Alocar 3 vetores via
`pci_alloc_irq_vectors` **não** faz o hardware usar 3 mensagens — ele continua
mandando tudo pelo vetor 0. É exatamente por isso que `bpcie_handle_edge_irq()`
existe: o demux não é um contorno, é a forma correta de lidar com esse hardware.

**Decodificação do `BPCIE_ACK_READ`** (BAR2 do glue, offset `0x110088`; o write é
`0x110084`): para a função 7, os bits **18:16** são os flags de pendência por
subfunção, **ativos em nível baixo**:

| `vec_read` | bits 18:16 | Pendentes |
|------------|------------|-----------|
| `0x001e0103` | `110` | só a 0 (USB) |
| `0x001c0103` | `100` | 0 e **1 (SATA)** |
| `0x001a0103` | `101` | 0 e 2 |

**Why:** foi criada a tag `20260728-sata-irq-dedicada` alterando
`bpcie_assign_irqs()` para alocar `subfuncs_per_func[7]=3` vetores, sob a hipótese
de que o AHCI perdia interrupções por dividir o vetor com o USB. A mudança
funcionou no nível de alocação (o `/proc/interrupts` passou a mostrar
hwirq 5344/5345/5346), não regrediu nada — **e não serviu para nada**, porque o
vetor novo nunca é disparado. A hipótese da "corrida no ACK compartilhado" também
está **refutada**: zero invocações vazias.

**How to apply:** não tentar dar vetor MSI dedicado a subfunções do Baikal — o
hardware não suporta. Reverter a mudança em `bpcie_assign_irqs()` (complexidade sem
benefício). Para o SATA, a pergunta real passou a ser **por que o glue para de
sinalizar a subfunção 1 como pendente**: a última interrupção do AHCI chegou aos
**4,907s** e nunca mais, e a falha aos 36,78s é só o timeout de 30s do SCSI
estourando sobre um comando emitido por volta dos 6,8s. Relacionado:
[[sata-interno-falha-e-ncq-irq-compartilhada-2026-07-28]].
