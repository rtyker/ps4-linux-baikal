---
name: marco-2026-07-23-gpu-gladius-firmware-real
description: Ativação com sucesso da GPU Gladius no PS4 Pro, confirmação de 32 CUs e extração do firmware genuíno do Orbis 12.52 via kexec
metadata:
  type: project
---

# Marco Histórico (2026-07-23): GPU Gladius Ativada e Firmwares Genuínos Salvos

No Kernel Linux 7.0 (tag `v7.0-20260722-clean-video-ok` / `20260723-mts-autoeth0`), foi verificada a inicialização da GPU **AMD Gladius** (`0x1002:0x9924`) no PS4 Pro real.

## Resultados Empíricos Obtidos:
1. **Driver `amdgpu` 3.64.0**: Inicializado sem erros de ring/fence (`-110`).
2. **32 Compute Units**: Reconhecimento completo dos 32 CUs da APU do PS4 Pro (`SE 4, SH per SE 1, CU per SH 9, active_cu_number 32`).
3. **Nós DRM**: `/dev/dri/card0` e `/dev/dri/renderD128` ativos.
4. **OpenGL 4.5 Core Profile & ES 3.2**: `direct rendering: Yes`, `Accelerated: yes`, 55.26 FPS cravados no VSync via `glxgears` sob Xorg.
5. **Vulkan 1.3 (radv)**: Driver `radv` Mesa 26.1.5 enumerou com sucesso a GPU `AMD DG1501SML87LB (RADV KAVERI)` (`0x1002:0x9924`).
6. **Extração via Kexec**: Confirmado que o kexec extrai do Orbis 12.52 RAM os firmwares reais do Gladius (`gladius_ce.bin`, `gladius_me.bin`, `gladius_mec.bin`, `gladius_mec2.bin`, `gladius_pfp.bin`, `gladius_rlc.bin`, `gladius_sdma.bin`, `gladius_sdma1.bin`).
7. **Backup em Repositório**: Baixados via `scripts/fetch_gladius_fw.py` para `distros/arch_minimal_v2/firmware_gpu/amdgpu/` e `consolidado/firmware_gladius_real/`.

Ver detalhamento em `consolidado/MARCO_HISTORICO_GPU_GLADIUS_REAL.md`.
