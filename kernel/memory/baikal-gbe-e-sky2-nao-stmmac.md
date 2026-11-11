---
name: baikal-gbe-e-sky2-nao-stmmac
description: "CAUSA RAIZ Ethernet PS4 Pro: a GBE Baikal (00:14.1, 104d:90d8) é um Marvell Yukon 2 (sky2), NÃO Synopsys/stmmac — stmmac gera Oops real (BAR0 4KB < offset DMA 0x1000); fix = adicionar BAIKAL_GBE ao sky2 + IRQs via bpcie"
metadata: 
  node_type: memory
  type: project
  originSessionId: dfd95c6f-d4a4-4437-929d-a734e0aa051c
  modified: 2026-07-18T13:49:32.898Z
---

> ⛔ **REFUTADO EM 2026-07-22 — NÃO SEGUIR A CONCLUSÃO DESTE ARQUIVO.**
> A afirmação "sky2 é o driver CORRETO para a GBE Baikal" está **errada**. O Orbis usa `msk`/Yukon
> para Aeolia/Belize, mas **`mts`/`mtsc_pci` (`sys/dev/mts/if_mts.c`) para o Baikal** — outro silício.
> A GBE também **nunca esteve desalimentada**: a BAR0 está viva (36 registradores não-zerados).
> O que continua válido aqui é apenas a refutação do `stmmac`. Ver
> [GBE-VIVA-driver-errado-mts-nao-sky2](GBE-VIVA-driver-errado-mts-nao-sky2.md).
**Descoberta 2026-07-17 (encerra a saga stmmac dos itens 9–11 do TENTATIVAS_7.0.md):** a Ethernet do PS4 Pro Baikal (`00:14.1`, `104d:90d8`) é um **Marvell Yukon 2**, atendida pelo driver **sky2** — o mesmo silício das gerações Aeolia (`0x909e`) e Belize (`0x90c9`), que o fork fail0verflow já suportava em `drivers/net/ethernet/marvell/sky2.c`. Só faltava o ID do Baikal na tabela e o roteamento de IRQ via **bpcie** (padrão copiado de `xhci-aeolia.c`). Fix: `distros/arch_minimal_v2/patches/sky2-baikal-gbe.patch` (tag `20260717-sky2baikal`).

**Por que o stmmac travava (prova, com foto do Oops):** o BAR0 da GBE tem só 4KB, e `dwmac4_dma_reset()` lê offset 0x1000 → `BUG: unable to handle page fault` (página não mapeada do ioremap), `ip[171] exited with irqs disabled` → sistema morre. O crash acontecia em `stmmac_open()` — por isso o probe "funcionava" e o travamento só vinha quando algo subia a interface (`netconsole=...eth0` nos initcalls, ou o `ip link set eth0 up` do initramfs de debug). Isso também explicou o "travamento ambíguo aos ~49min" do teste `fixedlink`: mesmo bug, colapso total com timing variável.

**Armadilha a não repetir:** os "sinais" de que era DWMAC ("Version ID not available", dma_cap zerada, MAC aleatória) eram leituras de registros de um hardware que não é DWMAC — lixo/zeros. Antes de escrever driver novo pra hardware Sony, **grep primeiro na árvore por suporte existente das gerações anteriores** (Aeolia/Belize) — o fork fail0verflow já resolveu muita coisa (sky2, xhci-aeolia, ahci, bpcie/apcie) e o padrão Baikal = "igual ao Aeolia mas com bpcie_*" se repete.

Detalhe técnico completo: TENTATIVAS_7.0.md item 11. Ver [[baikal-gbe-toque-trava-desliga-ps4]] (o travamento do `cat config` cru continua real e separado deste bug), [[sessao-2026-07-17-resumo-ethernet-stmmac]] (histórico da abordagem descartada).

## Bloqueio atual: MAC core clock/power gated (2026-07-18, mapeamento ICC ao vivo)


Com a tag `20260717-iccdbg` (`/proc/ps4_icc`) no PS4 real, mapeei o serviço ICC device-power ao vivo. **RESULTADO: a hipótese de que a GBE se liga por um minor do ICC device_power (major 5) está DESCARTADA.**

- GETs válidos `5 0x01`(wlan/bt) `5 0x11`(usb) `5 0x21`(hdd) `5 0x31`(bd) → todos respondem `00 00 01...` (ligado). O minor candidato **`5 0x41` (gbe) retorna `01 05...` — idêntico ao NAK de um minor inválido** (calibrei com `5 0x03`). Varri 0x51..0xf1: todos NAK. Ou seja, o serviço `icc_device_power` do EMC tem **exatamente 4 dispositivos** — bate com a página IOCTL do psdevwiki (`9C01..9C08` = wlan_bt/usb/hdd/bd control+get). **GBE não está no device_power do EMC.**
- Dump MMIO ao vivo da BAR0 (`dd if=/dev/mem`): byte chip id `B2_CHIP_ID`=0x11b **lê 0**, `B2_MAC_CFG`=0x11a lê 0, `B0_CTST`=0x004 lê 0 — MAS 0x000=0x79498100 e 0x008=0x0f597c00 leem valores reais e estáveis. **Assinatura de core do MAC Yukon com clock/power gated atrás de um wrapper PCIe que está ligado.** O `glue_set_region` NÃO é o problema (a BAR responde); o sky2_init roda o clock-enable padrão (`PCI_DEV_REG3=0` + `B0_CTST=CS_RST_CLR`) e mesmo assim chip id fica 0 → o gate é externo ao MAC.
- `devpm` do Syscon (não do EMC) mostra `# gbe off` — a GBE é uma **rail gerenciada pelo Syscon**, chip separado do EMC. O caminho pra ligá-la NÃO é o device_power do EMC. Candidatos remanescentes (todos RE aberto, risco crescente): (a) registrador de clock-gate na região "pervasive" do bpcie glue em BAR2 — análogo ao `BPCIE_USB_BASE=0x180000` que liga USB/SATA (offset da GBE desconhecido); (b) comando ICC num serviço diferente que faz o EMC pedir a rail ao Syscon; (c) byte de config na NVS (`offset 0x38` = "gbe related" na página NVS do psdevwiki) lido pelo EMC/Syscon no boot — **NVS write pode brickar, não fazer sem decisão do usuário**. `bpcie_glue_init` do Baikal não faz NENHUM `glue_set_region` (o Aeolia faz) — pode ou não ser relevante já que a BAR responde.
