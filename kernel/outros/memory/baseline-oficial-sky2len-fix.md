---
name: baseline-oficial-sky2len-fix
description: 20260720-sky2len-fix é a baseline oficial confirmada (vídeo OK) do kernel 7.0 Baikal — todo trabalho novo de GBE parte daqui, não das tags de 07-21/07-22.
metadata:
  type: project
---

Depois do incidente de perda de vídeo em 2026-07-22 (ver [incidente-2026-07-22-gbe-release-boot-travou-video](incidente-2026-07-22-gbe-release-boot-travou-video.md)), foi feita uma bisecção ao vivo testando tags pré-compiladas de `distros/arch_minimal_v2/boot_referencia/` direto no PS4:

| Tag | Data | Resultado ao vivo |
|---|---|---|
| `20260722-clean-video-ok` | 22/07 | ✅ **CONFIRMADO AO VIVO: vídeo OK, boot completo, telnet OK** |
| `20260722-gbe-release-safe` | 22/07 | tela preta (commit `d3fa7b72c`, hold/pulse GBE automático no boot) |
| `20260722-gbe-revertido` | 22/07 | tela preta (rebuild limpo com patch sky2 antigo) |
| `20260721-gbe-hold-release` | 21/07 | **travou/congelou** (mesma classe de write hold/pulse na GBE) |
| `20260720-sky2len-fix` | 20/07 | ✅ **vídeo OK, boot completo** (baseline pré-compilada) |
| `20260717-sky2baikal` | 17/07 | ✅ vídeo OK (baseline mais antiga, ainda válida) |

**Conclusão:** `v7.0-20260722-clean-video-ok` (git tag no repo do kernel `/mnt/hdauxiliar/temp/kernel_build_7.0`, commit `811184c1f`) é a **baseline oficial confirmada de compilação limpa a partir do zero**.

**GAP DE REBUILD RESOLVIDO E COMPROVADO AO VIVO (2026-07-22):**
1. O patch `sky2-baikal-gbe.patch` aplicava o ID `104d:90d8` ao driver `sky2` embutido (`CONFIG_SKY2=y`). Ao dar probe na GBE Baikal (que é Sony MTS e não Marvell Yukon), o `sky2` travava o barramento PCIe e apagava o vídeo.
2. Removido o `sky2-baikal-gbe.patch` do script `00-build-kernel-7.0.sh` e garantidas as opções `CONFIG_MFD_SYSCON=y` e `CONFIG_REGMAP_MMIO=y`.
3. Reconstrução testada ao vivo no console PS4 real: **vídeo recuperado com sucesso e telnet 100% funcional!**

**Artefatos Protegidos:** `distros/arch_minimal_v2/boot_referencia/*-7.0-20260722-clean-video-ok*` e `config-7.0-20260720-sky2len-fix`.

**Regra permanente de segurança já validada 2x:** nenhum write direto de hold/pulse/reset em registradores da GBE (BAR2 glue, offsets tipo `0x20`/`0x74` relativos a `BPCIE_USB_BASE`) no caminho de boot do kernel — trava (`gbe-hold-release`) ou apaga o vídeo (`gbe-release-safe`) toda vez que foi tentado. Qualquer novo experimento de "ligar" a GBE deve ser feito por leitura primeiro (ex: efuse/trim de validade em `BAR4+0xc000+0x6c`, bits 23/31 — ver `consolidado/RE_KERNEL_GBE_ATTACH.md`) e, se precisar de write, testar manualmente via telnet/devmem fora do kernel antes de cogitar automatizar no boot.
