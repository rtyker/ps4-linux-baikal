---
name: sata-interno-falha-e-ncq-irq-compartilhada-2026-07-28
description: Falha do HD interno SATA é perda de conclusão NCQ por IRQ MSI compartilhada, não PHY nem SMR
metadata:
  type: project
---

A falha do HD interno (TOSHIBA MQ04ABF100, `ata1`, `0000:00:14.7`) **não** é PHY,
calibração EFUSE, power domain nem garbage collection do SMR. Em 100% dos logs a
falha é um `READ FPDMA QUEUED` (NCQ) que nunca completa, com `Emask 0x0`,
**`SErr 0x0`** e `status { DRDY }` — ou seja, zero erro de link, drive saudável,
link estável em 3.0 Gbps antes e depois.

> 🔴 **CORREÇÃO 2026-07-28 (pós-teste ao vivo) — A AFIRMAÇÃO ABAIXO ESTAVA ERRADA.**
> O AHCI **sempre teve** handler de IRQ registrado. Ele não se chama `ahci[0000:00:14.7]`
> e sim **`xhci_aeolia[0000:00:14.7]`**, porque `ata_host_activate()`
> (`libata-core.c:6206`) monta o nome com `dev_driver_string(host->dev)` — o driver
> ligado ao dispositivo PCI, que é o `xhci_aeolia`, não o `ahci`. Procurar por
> "ahci[...]" em `/proc/interrupts` para esta função é um falso negativo garantido.
> O AHCI do Blu-ray aparece como `ahci[0000:00:14.2]` só porque aquele dispositivo
> está ligado diretamente ao driver `ahci`.
>
> **O que era verdade:** o AHCI *compartilhava* a IRQ 32 com os dois xHCI. Isso foi
> corrigido — ver "resultado do teste" no fim deste arquivo.

**Afirmação original (INCORRETA), preservada para rastreabilidade:** ~~não existe
`ahci[0000:00:14.7]` em linha nenhuma — o AHCI do HD interno não tem handler de
interrupção registrado.~~ Todos os outros Baikal aparecem (`icc` hwirq 5251, xHCI
5344, `mmc0` 5216, `ahci[0000:00:14.2]` 5184, `mts` 5152). O vetor que faltaria é
hwirq **5345** = func 7 subfunção 1. O boot anuncia `ata1 ... irq 32`, mas a IRQ 32
só tem handlers xHCI.

Causa confirmada: `bpcie_assign_irqs()` (`drivers/ps4/ps4-bpcie.c:273`) força
`nvec = 1` para toda função que não seja a glue (func 4), então
`xhci_aeolia_irqnum()` (`drivers/usb/host/xhci-aeolia.c:78`) devolve `dev->irq`
para o AHCI. Resultado: **AHCI e os dois barramentos xHCI dividem a IRQ 32**, e o
rootfs fica no USB. Conclusão NCQ depende exclusivamente do SDB FIS; interrupção
perdida = tag pendente para sempre. O AHCI do Blu-ray (`0000:00:14.2`) tem IRQ 36
dedicada e nunca falha — serve de controle.

**Why:** o plano anterior perseguiu PHY/EFUSE por meses com base em três erros de
leitura de log: (1) afirmava que `noncq` foi testado e falhou igual, mas os logs
que falham mostram `applying quirks: nolpm` apenas, com `NCQ (depth 32), AA`
ligado; (2) afirmava timer fixo de 31.85s, mas as falhas ocorrem em 31.84s,
36.58s e 44.76s; (3) afirmava que o HD é soldado, mas a placa é NVG-002 (PS4
Slim) com gaveta removível.

**Correção aplicada 2026-07-28 (build pendente):** em `ps4-bpcie.c`, o clamp
`nvec = 1` virou `nvec = min(nvec, bpcie_max_vectors(PCI_FUNC(dev->devfn)))`, com
helper novo que devolve `subfuncs_per_func[func]` só para as funções com ramo de
demux em `bpcie_handle_edge_irq()` — 4 (glue), 5 (DMAC) e 7 (xHCI). As funções 0
(ACPI) e 6 (MEM) ficam em 1 porque não têm demux, e um vetor extra ali nunca seria
acked. Efeito prático: só a função 7 muda (1 → 3 vetores); `mmc0`, `mts` e o AHCI
do Blu-ray já pediam menos que o próprio limite. Nada precisou mudar em
`xhci-aeolia.c`. Tag planejada: `20260728-sata-irq-dedicada`, e o `noncq` tem de
sair do bootargs dela senão a validação não prova nada.

**How to apply:** antes de investigar PHY em qualquer subsistema Baikal, checar
`SErr` — se for `0x0`, o PHY está bom e o problema é entrega de interrupção ou
software. Ler os `.bin` de `tests/uart_logs/` com
`strings -n 4 arquivo.bin | grep -i ata`; os `.log` de mesmo nome são hexdump e
não servem para grep de texto. Plano completo em
`PLANO_SATA_INTERNO_100PCT_2026-07-28.md`. Relacionado:
[[baikal-gbe-e-sky2-nao-stmmac]], [[bar4-efuse-corrigido-mas-phy-continua-mudo-2026-07-23]].

## Resultado do teste ao vivo (2026-07-28, tag `20260728-sata-irq-dedicada`)

**A correção de IRQ FUNCIONOU como projetada.** `/proc/interrupts` depois do deploy:

```
32:  8212  Baikal-MSI 5344-edge  xhci-hcd:usb1
33:     7  Baikal-MSI 5345-edge  xhci_aeolia[0000:00:14.7]   <- este É o AHCI
34:     1  Baikal-MSI 5346-edge  xhci-hcd:usb3
```

Os 3 vetores da função 7 foram alocados (hwirq 5344/5345/5346) e o AHCI ficou sozinho
no 5345, exatamente o vetor previsto. `ata1: ... irq 33` confirma.

**Mas o HD continua falhando**, e de forma que REFUTA a hipótese de NCQ:

```
[   31.843849] ata1.00: exception Emask 0x0 SAct 0x0 SErr 0x0 action 0x6 frozen
[   31.844999] ata1.00: failed command: READ DMA
[   31.846102] ata1.00: cmd c8/00:08:00:00:00/00:00:00:00:00/e0 tag 22 dma 4096 in
```

`READ DMA` (opcode `0xc8`, `SAct 0x0`) é comando **não-enfileirado**. Ou seja, não é
específico de NCQ — qualquer comando que dependa de interrupção para completar não
completa. `SErr 0x0` continua zerado (link OK).

**Pista nova e forte:** o contador da IRQ 33 parou em **7**. O AHCI recebeu algumas
interrupções durante o probe e depois nada. Não é que o handler falte — é que a
**entrega de interrupção cessa depois do probe**. Investigar o demux
`bpcie_handle_edge_irq()` no ramo `func == 7` (`mask = 7`, `shift = 0x10`): se o bit da
subfunção 1 não for reportado/ACKed corretamente em `BPCIE_ACK_READ`, o dispatch para
hwirq 5345 para de acontecer.

**Atenção — `noncq` NÃO sai pelo bootargs:** o quirk está hardcoded em
`drivers/ata/libata-core.c:4199` (`{ "TOSHIBA MQ04ABF100", NULL, ATA_QUIRK_NOLPM |
ATA_QUIRK_NONCQ }`), adicionado em sessão anterior. Remover do cmdline não reativa NCQ —
o boot ainda mostrou `applying quirks: noncq nolpm`.
