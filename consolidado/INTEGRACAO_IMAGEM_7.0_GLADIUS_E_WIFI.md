# Integração da Imagem Arch 7.0: GPU AMD Gladius, Aceleração 3D e WiFi MT7668

**Data:** 23 de Julho de 2026  
**Kernel Alvo:** Linux 7.0.8 (Strawberry Baikal)  
**Script Principal de Imagem:** [`distros/arch_minimal_v2/01-build-image-7.0.sh`](file:///mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/01-build-image-7.0.sh)

---

## 1. O que foi Atualizado na Imagem Oficial de Produção

### 1.1 Inclusão dos Pacotes Gráficos 3D & Xorg (Item 1)
O script de montagem da imagem Arch Linux (`01-build-image-7.0.sh`) foi atualizado para incluir os seguintes pacotes gráficos nativamente no array `PKGS`:
- `mesa` & `lib32-mesa` (Drivers OpenGL/EGL RadeonSI)
- `vulkan-radeon` & `lib32-vulkan-radeon` (Driver Vulkan RADV 1.3 para CIK/Gladius)
- `vulkan-tools` (`vulkaninfo`)
- `mesa-utils` (`glxinfo`, `glxgears`)
- `xorg-server`, `xorg-xinit`, `openbox` (Servidor gráfico X11 e Gerenciador de Janelas)

### 1.2 Inclusão dos Firmwares Genuínos AMD Gladius (PS4 Pro) (Item 1)
O script agora copia os 8 microcódigos genuínos da GPU Gladius extraídos via `kexec` para o diretório `/lib/firmware/amdgpu/` do rootfs:
- `gladius_ce.bin`
- `gladius_me.bin`
- `gladius_mec.bin`
- `gladius_mec2.bin`
- `gladius_pfp.bin`
- `gladius_rlc.bin`
- `gladius_sdma.bin`
- `gladius_sdma1.bin`

### 1.3 Suporte ao WiFi/Bluetooth MediaTek MT7668 (Item 3)
- O firmware oficial do Bluetooth `mt7668pr2h.bin` foi baixado e armazenado em `distros/arch_minimal_v2/firmware_wifi/mediatek/` e `extra_firmware/mediatek/`.
- O script `01-build-image-7.0.sh` copia automaticamente os firmwares MediaTek (`mt7668pr2h.bin` e `WIFI_RAM_CODE_MT7668.bin`) para `/lib/firmware/mediatek/` na partição rootfs.
- O kernel `00-build-kernel-7.0.sh` já embute a suíte MT7668 via `CONFIG_EXTRA_FIRMWARE`.

---

## 2. Como Gerar o Novo Tarball de Produção

Para aplicar as mudanças e gerar a nova imagem de produção pronta para o PS4:

```bash
cd /mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2
sudo ./01-build-image-7.0.sh
```

Isso gera a imagem atualizada `arch_minimal_v2-7.0.tar` e o `initramfs-7.0.cpio.gz` pronto para o `02-burn-image.sh`.
