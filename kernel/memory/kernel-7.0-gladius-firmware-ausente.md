---
name: kernel-7-0-gladius-firmware-ausente
description: Causa raiz da tela preta no kernel 7.0 Baikal — firmware gladius da GPU embutido vazio (0 bytes)
metadata: 
  node_type: memory
  type: project
  originSessionId: e8e1b668-803e-44e6-9095-8f8755a1e265
---

No kernel 7.0 (rmuxnet/linux, branch baikal/7.0.8-Stable) o boot dava tela preta apesar do kernel estar vivo (numlock/USB/HID/SATA/xHCI todos OK, confirmado via initramfs de debug que grava dmesg em FAT).

**Causa raiz:** o driver amdgpu falha em `cik_sdma: Failed to load firmware "gladius_sdma.bin"` → `early_init failed -22` → `Fatal error during GPU init`. Os arquivos `extra_firmware/amdgpu/gladius_*.bin` foram criados VAZIOS (0 bytes) pelo `touch` de fallback no `00-build-kernel-7.0.sh`, porque o firmware real vem de repo privado `sony-jaguar-devs/orbis_gpu_blobs_ps4` (inacessível). O kernel embutiu esses blobs vazios via CONFIG_EXTRA_FIRMWARE.

**Diferença vs 5.4 neocine (que funciona):** o 5.4 NÃO embute firmware de GPU (CONFIG_EXTRA_FIRMWARE só tem WiFi mrvl/mediatek) — carregava gladius do rootfs em /lib/firmware/amdgpu/. Esse rootfs 5.4 com gladius real foi perdido/sobrescrito.

**Firmware gladius real NÃO existe em lugar nenhum do sistema.** O dump `nor_sflash0.bin` (32MB NOR flash) NÃO contém firmware de GPU — só WiFi calibration (C0020001). Só temos `liverpool_*.bin` reais (ago/2021, do initramfs PS4 Linux original) em `/mnt/hdauxiliar/temp/kernel_build_7.0/extra_firmware/amdgpu/` e `/mnt/hdauxiliar/temp/initramfs_check/lib/firmware/amdgpu/`.

**Console:** PS4 Pro Baikal B1, GPU GLADIUS (PCI 0x1002:0x9924). IDs 0x9920/22/23 = LIVERPOOL, 0x9924 = GLADIUS no amdgpu_drv.c.

**Estratégia testada (2026-07-16): liverpool_*.bin copiado como gladius_*.bin, rebuild incremental (tag 20260716-gladiusfw).** RESULTADO PARCIAL:
- SDMA, GMC, VRAM (1024M), IH, DCE v8, display connectors HDMI-A-1 → TODOS OK com firmware liverpool. Sumiu o "Failed to load gladius_sdma.bin".
- MAS trava em `gfx_v7_0`: `ring gfx test failed (-110)` (timeout) → `hw_init of IP block <gfx_v7_0> failed` → Fatal. Os firmwares GFX carregam (sem erro de load) mas o Command Processor do Gladius NÃO executa o microcódigo do Liverpool. Tela preta persiste.
- **Conclusão:** microcódigo CP/GFX (ce/me/mec/mec2/pfp/rlc) do Gladius (PS4 Pro) é DIFERENTE do Liverpool e precisa ser o REAL. Só o SDMA é compatível. `DID mismatch` de clock (liverpool_clk.c) é só warning, não é o bloqueador.
- dmesg salvo em `distros/arch_minimal_v2/firmware_gpu/dmesg-7.0-liverpoolfw-gfxfail.txt`.
- Para vídeo: precisa dump do gladius CP real do console (fail0verflow ps4-kexec firmware.c).

**Firmwares consolidados em `distros/arch_minimal_v2/firmware_gpu/amdgpu/` + README.** Build incremental (só firmware muda) leva ~5min via `make -j7 LLVM=1 bzImage` no tree, não 40min.

**Outras pendências 7.0:** Ethernet sky2 não sobe (problema Baikal GBE conhecido/não resolvido, BAIKAL_GBE comentado). WiFi MT7668 faltam blobs completos no boot (wifi.cfg, WIFI_RAM_CODE_MT7668.bin, patches e0/e2) — existem em extra_firmware/ do build 7.0.

**ATUALIZAÇÃO 2026-07-17 — firmware real via kexec testado, MESMO ERRO persiste.** Tag `20260716-gladiusreal-stmmac` (kernel com `CONFIG_EXTRA_FIRMWARE` sem gladius, deixando o kexec injetar o firmware real da RAM do Orbis no initramfs — ver [[sessao-2026-07-16-pausada-onde-continuar]]) foi testada no PS4 real. Resultado lido via log FAT (`PS4_DMESG_449.txt`, tela continuou preta):
```
[    1.158568] amdgpu 0000:00:01.0: [drm:amdgpu_ring_test_helper] *ERROR* ring gfx test failed (-110)
[    1.158593] amdgpu 0000:00:01.0: hw_init of IP block <gfx_v7_0> failed -110
[    1.158611] amdgpu 0000:00:01.0: Fatal error during GPU init
```
Exatamente o mesmo erro/timestamp do teste com firmware liverpool-como-substituto. **Nenhuma linha de firmware (request/load/erro) aparece no dmesg entre a detecção do gfx_v7_0 e o timeout** — não dá para confirmar pelo log se o kexec conseguiu injetar o firmware real dessa vez (sem erro visível, mas também sem confirmação de carga). Duas hipóteses em aberto: (a) a injeção do kexec falhou silenciosamente e o gfx ainda rodou sem microcódigo válido, ou (b) o firmware real também não resolve o -110 — a causa seria outra (setup de registrador/doorbell/IRQ do CP, não o conteúdo do microcódigo). **Próximo passo sugerido:** conectar via telnet BEM no início do boot (WiFi associou ~6min de uptime nesse teste, tag `wifissh`/`gladiusreal-stmmac` usam o mesmo initramfs debug) e checar ao vivo `ls -la /lib/firmware/amdgpu/gladius_*.bin` (tamanho/checksum) antes de tirar conclusões sobre a hipótese do firmware.
