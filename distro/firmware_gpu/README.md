# Firmware GPU PS4 (amdgpu) — Liverpool / Gladius

Pasta criada em 2026-07-16 para consolidar o firmware da GPU do PS4 e **não
precisar procurar de novo**. Contém o que existe de fato no projeto.

## O que temos aqui (`amdgpu/`)

| Arquivo | Origem | Tamanho |
|---|---|---|
| `liverpool_*.bin` (ce, me, mec, mec2, pfp, rlc, sdma, sdma1, uvd, vce) | Firmware REAL, do initramfs 5.4 que funciona (`boot_referencia/initramfs.cpio.gz`) e do build tree. Datados de ago/2021. | 4KB–232KB |
| `gladius_*.bin` | **Cópia** dos `liverpool_*.bin` correspondentes (veja justificativa abaixo). | idem |

## Por que gladius = cópia de liverpool

- O console é um **PS4 Pro (Baikal B1)**, GPU **GLADIUS** (PCI `0x1002:0x9924`).
  Confirmado no dmesg real do kernel 7.0.
- O driver amdgpu (tanto 5.4 neocine quanto 7.0) pede `amdgpu/gladius_*.bin`
  por nome fixo, **sem fallback** (`cik_sdma.c`, `gfx_v7_0.c`).
- **O firmware gladius REAL nunca existiu neste projeto.** Verificado em: toda a
  pasta do projeto, os tars de rootfs (`arch_minimal_v2*.tar`, psxitarch, cachy,
  etc), o dump do NOR (`nor_sflash0.bin` — só tem WiFi calibration, não GPU),
  os kernels pré-compilados, e os repos públicos testados
  (feeRnt/ps4-linux-*, eeply/ps4-linux, *ps4-linux-initramfs*). O firmware
  gladius do PS4 Pro é distribuído por repo PRIVADO
  (`sony-jaguar-devs/orbis_gpu_blobs_ps4`) ou dumpado do próprio console
  (método fail0verflow `ps4-kexec/firmware.c`).
- **Evidência de que liverpool serve:** o initramfs do 5.4 que funcionava
  (com glxgears) continha SOMENTE `liverpool_*.bin` em `/lib/firmware/amdgpu/`,
  nenhum gladius. Liverpool (Fat/Slim) e Gladius (Pro) são a mesma geração
  GCN 2 / Sea Islands (CIK, `gfx_v7`); o microcódigo de engine (CP/SDMA/RLC)
  é compatível. As diferenças Pro↔Slim (nº de CUs) estão nos golden registers
  do kernel, não no microcódigo.

## Como conseguir o gladius REAL (se o liverpool-as-gladius não bastar)

1. Dump do próprio console: método fail0verflow `ps4-kexec/firmware.c` extrai
   os blobs da RAM do Orbis rodando. É a fonte correta e definitiva.
2. Recurso gbatemp #39211 "Registres AMDGPU gladius" (atrás de login).
3. Repo privado `sony-jaguar-devs/orbis_gpu_blobs_ps4` (usado pelo `build.sh`
   do kernel 7.0 via secret FW_REPO_PAT).

## SHA256 (liverpool reais)
```
173ff0d1...  liverpool_ce.bin
ab835c37...  liverpool_me.bin
e86d5846...  liverpool_mec.bin
f3250bc6...  liverpool_mec2.bin
d2b3ce93...  liverpool_pfp.bin
8c26efaa...  liverpool_rlc.bin
638602157... liverpool_sdma.bin
8bb8fc32...  liverpool_sdma1.bin
30eed8d6...  liverpool_uvd.bin
fb768657...  liverpool_vce.bin
```
