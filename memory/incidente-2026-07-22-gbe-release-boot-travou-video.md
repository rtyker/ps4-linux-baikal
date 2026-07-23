---
name: incidente-2026-07-22-gbe-release-boot-travou-video
description: Commit d3fa7b72c (bpcie_baikal_gbe_release automático no boot) derrubou o vídeo do PS4; revertido no mesmo dia.
metadata:
  type: project
---

Em 2026-07-22, o commit `d3fa7b72c` ("feat(gbe): baikal gbe hold release bit 10 pulse & sky2 resource length fix") no repo `/mnt/hdauxiliar/temp/kernel_build_7.0` (branch `baikal/7.0.8-Stable`, tag `v7.0-20260722-gbe-release-safe`) fez o PS4 parar de dar vídeo (tela preta, sem nenhum log de boot). O commit foi **revertido** com `git revert d3fa7b72c` (novo commit `53d112017`), restaurando a árvore ao estado de `d8cbb8e91`.

O que o commit fazia: adicionava `bpcie_baikal_gbe_release()` em `drivers/ps4/ps4-bpcie.c`, que escreve diretamente em registradores físicos MMIO do BAR2 glue (`BPCIE_GBE_HOLD_OFF=0x20`, `BPCIE_GBE_PULSE_OFF=0x74`, relativos a `BPCIE_USB_BASE=0x180000`) para tirar o bloco GBE do reset — via um par hold/pulse, no mesmo estilo do pulso de bit 10 já testado manualmente em `harness_gbe.py` (Bloco 9, offsets `0xc890a030`/`0xc890a034`). A diferença crítica: esse write passou a rodar **automaticamente e sem condição** dentro do probe do `sky2` para o dispositivo Baikal GBE, em todo boot (via `module_param gbe_release` default `true`) — bem antes do console de vídeo aparecer. O commit também trocava `ioremap(pci_resource_start(pdev,0), 0x4000)` por `ioremap(..., pci_resource_len(pdev,0))` no `sky2_probe`, uma segunda mudança não descartada como causa alternativa.

**Por que:** writes crus em regiões BAR2 (`0xc890a0xx`) da Baikal já tinham travado/desligado o PS4 antes (ver regra no `CLAUDE.md`/`MEMORY.md`: `cat .../config` do GBE travou reproduzivelmente em 2026-07-16, e a regra "NUNCA fazer block-read/varredura contígua na região pervasive BAR2"). O próprio autor do commit já sabia do risco — por isso incluiu o parâmetro `gbe_release` como "rota de recuperação" via bootarg — mas deixou o padrão como `true` (ativo), rodando incondicionalmente no boot em vez de como teste manual controlado.

**Como aplicar:** antes de reintroduzir esse tipo de write de hardware (hold/pulse, power-gate, etc.) no caminho de boot do kernel, ele precisa ser **opt-in por padrão** (`gbe_release=false`/equivalente) e testado primeiro manualmente via bootarg ou via harness de telnet (mesmo padrão usado em `harness_gbe.py`) antes de virar comportamento automático. Só promover a default depois de confirmar ao vivo que não trava/desliga o console e que o vídeo continua íntegro. Ver também [baikal-gbe-toque-trava-desliga-ps4](baikal-gbe-toque-trava-desliga-ps4.md) e [feedback-dados-live-harness-sobrepoe-docs-antigos](feedback-dados-live-harness-sobrepoe-docs-antigos.md).

**Estado após o incidente:** revertido, repo limpo em `53d112017` (equivalente funcionalmente a `d8cbb8e91`). Próximo passo do GBE deve ser decidido a partir do levantamento já feito (`harness_gbe.py` + `harnes_gbe_reandoly.py`), mas reintroduzindo qualquer write de hardware como opt-in/testável manualmente primeiro, não direto no boot path.
