---
name: gbe-fase2-msi-imr-refutada-2026-07-30
description: Fase 2/3 do plano GBE concluída e refutada ao vivo — MSI da GBE não está mascarado em hardware, IMR real desmascarado (0x7d) não gera nenhum IRQ, PHY genuinamente não sinaliza nada. Não reabrir sem dado novo. Bônus - bug de WARNING no rmmod.
metadata:
  type: project
---

## Fase 2/3 do `PLANO_MTS_SOLUCAO_CONSOLIDADO_2026-07-29.md` — CONCLUÍDA E REFUTADA (2026-07-30)

Testes feitos ao vivo no baseline `20260730-sata-reverted` (ver
[[baseline-oficial-20260730-sata-reverted]]), **sem nenhum rebuild/power-cycle** — decidiram a
questão antes de precisar mexer em `ps4-bpcie.c`.

### O que motivou o teste
No boot anterior, `dmesg` mostrava `mts.ko` logando `RX_CLEAN ... cleaned=N` a cada ~16s.
**Esclarecimento:** isso não é atividade de hardware — é só o contador de chamadas de NAPI
poll (`mp->rx_debug_logs`, logado a cada 1000 polls, `mts.c:1608-1685`), com o descritor
`idx=0` sempre `OWN=1` (buffer vazio). Não é pista nova, é ruído de debug.

### Teste 1 — MSI da GBE está mascarado em hardware (como o AHCI)?
`lspci -vv -s 0000:00:14.1`:
```
Capabilities: [e0] MSI: Enable+ Count=1/1 Maskable+ 64bit+
	Address: 00000000fee05000  Data: 0024
	Masking: 00000000  Pending: 00000000
```
**`Masking: 00000000` — NÃO mascarado**, diferente do caso AHCI documentado em
`DESCOBERTA_SATA_MSI_MASKING_2026-07-29.md` (`Masking: 000000fe`, bit 1 mascarado).
Refuta de cara a hipótese "mesmo bug do SATA" para a GBE.

### Teste 2 — IMR (software) está mascarando eventos reais?
Achado adicional durante a investigação: o parâmetro de módulo `irq_mask` do `mts.ko` tem
**default `0x0`, que o próprio comentário do código descreve como "tudo mascarado"**
(`drivers_mts/mts.c:106-109`). Ou seja, em todo boot anterior o driver nunca habilitou
nenhuma fonte de IRQ real — isso por si só bastaria para explicar `irq_count` baixo.

Testado: `rmmod mts` (gerou um `WARNING: kernel/irq/msi.c:294 at msi_device_data_release`,
não-fatal — ver seção "achado colateral" abaixo) + `insmod mts.ko stage=4 irq_mask=0x7d`.
Confirmado via `mts_regs`: `+0x054 = 0x0000007d`. Resultado após 5+s:
- `/proc/interrupts`: linha `mts` (`5152-edge`) ficou em **`irq_count=0`**.
- `ping 192.168.0.1↔192.168.0.2`: 100% perda.
- `eth0`: continuou `NO-CARRIER`.

**Refuta também a hipótese do IMR** — mesmo com interrupções realmente desmascaradas no
hardware do MAC, zero eventos chegam.

### Conclusão (Fase 3 do plano, decisão de continuidade)
Nem mascaramento de MSI (hardware) nem IMR (software) explicam o bloqueador. **O PHY
genuinamente nunca gera nenhuma condição de IRQ** (nem link change, nem RX) — o problema é
anterior a qualquer coisa que o driver Linux possa fazer: energia/clock físico do PHY que
nunca chega, ou uma sequência de bring-up feita pela Sony fora do alcance replicável via
software puro (SAMU/bootloader). **A mudança de código em `ps4-bpcie.c` cogitada na Fase 2 do
plano não é necessária** — conferido que o código de demux de MSI já está correto para a GBE
(requisita vetor único via `bpcie_assign_irqs(pdev, 1)`, não passa por nenhum caso especial em
`bpcie_handle_edge_irq`, que só trata func 4/glue e func 7/xHCI).

**Esta via de investigação está formalmente encerrada.** Não repetir sem dado concreto novo
(candidato: engenharia reversa da sequência de bring-up do PHY via SAMU/ICC feita pelo Orbis,
ainda não tentada). Ver `consolidado/BACKLOG.md` e `test_history` id 72 no
`ps4_hardware_memory.db`.

### Achado colateral (não bloqueia, não é causa raiz) — bug de WARNING no rmmod
`rmmod mts` produz, de forma reprodutível, um `WARNING: kernel/irq/msi.c:294 at
msi_device_data_release+0x37/0x40` durante `pci_unregister_driver → driver_detach →
device_unbind_cleanup → devres_release_all`. O sistema **não trava** (fica só `Tainted: [O]`)
e o `insmod` seguinte funciona normalmente. Indica algo no caminho de liberação de recursos
MSI do driver que não está fazendo o cleanup exatamente como o kernel espera (possivelmente
relacionado ao uso de `bpcie_assign_irqs`/`bpcie_free_irqs` customizados em vez do fluxo
padrão `pci_alloc_irq_vectors`/`pci_free_irq_vectors`). Não investigado a fundo — só
documentado aqui para não ser confundido com um crash real numa sessão futura.
