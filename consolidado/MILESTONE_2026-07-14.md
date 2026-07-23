# Milestone: PS4 Linux Arch Minimal v2 - 2026-07-14

## Status: FUNCIONAL ✅

PS4 (Baikal, CUH-2xxx) bootando Linux via SSH em 192.168.6.128

---

## Hardware Confirmado

| Componente | Detalhes |
|------------|----------|
| **GPU** | AMD Gladius (Liverpool APU) - PCI 1002:9924, GCN 2.0 / CIK |
| **VRAM** | 1024 MB GDDR5 (0xF0000000-0xF3FFFFFF) |
| **Display** | HDMI-A-1, DCE v8.0, encoder DFP1:INTERNAL_UNIPHY |
| **Bridge** | ps4_bridge (custom Sony), VIC mode 16 = 1080p60 |
| **EDID** | Samsung M8N4627 9" (somente 1920x1080@60 no EDID) |
| **Audio** | HDMI Audio 1002:9921 (snd_hda_intel) |
| **CPU** | AMD DG1501SML87LB (Jaguar, 8 cores, 1.6GHz) |
| **RAM** | 7 GB DDR3 (unificada) |

---

## Kernel & Boot

| Item | Valor |
|------|-------|
| **Kernel** | 5.4.247-neocine-1.1 (ps4-linux-12xx, branch v5.4.247__neocine-1.1) |
| **Initramfs** | better-initramfs baseado (hooks: early, init) |
| **Bootloader** | kexec via payload (PSFree/GoldHEN) |
| **Boot partition** | FAT32 (/dev/sda1) - bzImage, initramfs.cpio.gz, bootargs.txt, vram.txt, bootlog.txt |
| **Rootfs** | ext4 (/dev/sda2) - LABEL=psxitarch |

### Kernel Command Line (bootargs.txt)
```
panic=0 clocksource=tsc consoleblank=0 net.ifnames=0
radeon.dpm=0 amdgpu.dpm=0 drm.debug=0x06
console=ttyS0,115200n8 console=tty0
video=HDMI-A-1:1920x1080@60
drm.edid_firmware=edid/ps4_tv_edid.bin
quiet amdgpu.audio=1 usbcore.autosuspend=-1
amdgpu.gpu_recovery=1 mitigations=off zswap.enabled=1
systemd.unified_cgroup_hierarchy=0
systemd.legacy_systemd_cgroup_controller=yes
audit=0
netconsole=6665@192.168.0.2/eth0,6666@192.168.0.1/b4:45:06:6c:f6:4f
```

### Configs Importantes
- `CONFIG_DRM_AMDGPU_CIK=y` (Gladius = CIK/Sea Islands)
- `CONFIG_DRM_AMD_DC=y` + `CONFIG_DRM_AMD_DC_DCN1_0=y` (DCE v8)
- `CONFIG_DRM_LOAD_EDID_FIRMWARE=y` (EDID override)
- `CONFIG_DRM_FBDEV_EMULATION=y` (fbcon)
- `radeon.dpm=0 amdgpu.dpm=0` (power management DESLIGADO - clocks fixos)

---

## Próximos Passos — Kernel 5.15 LTS (Upgrade Mesa 22-25.x)

**Status do Trabalho**: 🚧 Em processo de portabilidade e testes de boot no Baikal. A compilação é bem-sucedida via `00-build-kernel-5.15.sh`, porém o boot ainda não obteve sucesso (luz branca/tela preta).

**Script:** `00-build-kernel-5.15.sh` (novo, não modifica scripts existentes)

### Objetivo
Migrar de kernel 5.4 (DRM 3.35) → 5.15 LTS (DRM 3.42+) para habilitar Mesa 22.x-25.x e repo DionKill.

### Mudanças necessárias no kernel 5.15
| Componente | Patch / Config |
|------------|----------------|
| **ps4_bridge** | HDMI/DP bridge driver (VIC modes, EDID override) |
| **ps4_smc / ps4_ahu** | Power management, fan, thermal |
| **VRAM carveout** | `vram.txt` via cmdline, memory reserved |
| **MediaTek MT7668** | WiFi/BT via SDIO (firmware .bin não .zst) |
| **Sky2 / STMMAC** | Baikal GbE (PCI ID 0x90d8) |
| **EDID firmware** | `drm.edid_firmware=edid/ps4_tv_edid.bin` |
| **AMDGPU CIK** | Gladius / Liverpool support |

### Repo base
```bash
git clone https://github.com/codedwrench/ps4-linux -b 5.15
```

### Build
```bash
sudo ./00-build-kernel-5.15.sh
# Gera: boot_referencia/bzImage-5.15  +  boot_referencia/config-5.15
```

### Teste
1. Copiar `bzImage-5.15` → partição FAT32 boot
2. Ajustar `bootargs.txt` se necessário
3. Boot via payload → validar: HDMI, Ethernet, WiFi, SSH, Mesa (DionKill repo)

### Benefício pós-upgrade
- Mesa 22.x-25.x via repo `ps4-video` (DionKill) ou AUR
- OpenGL 4.6 + Vulkan RADV (Gladius = CIK/GCN 2.0)
- glxgears / games com aceleração HW completa

---

## Funcionalidades Implementadas

### ✅ Vídeo/Display
- [x] HDMI 1080p60 forçado via `video=HDMI-A-1:1920x1080@60`
- [x] EDID firmware override (`drm.edid_firmware=edid/ps4_tv_edid.bin`)
- [x] EDID binário salvo em `/lib/firmware/edid/ps4_tv_edid.bin` (256 bytes)
- [x] Framebuffer `/dev/fb0` - 32bpp, 1920x1080, stride 7680
- [x] ps4_bridge driver funcional (VIC mode 16)
- [x] Modo persistente mesmo com TV desligada (EDID firmware)

### ✅ Rede
- [x] SSH (dropbear/openssh) - root/ps4
- [ ] Ethernet (Baikal GbE via sky2 driver) — **INCORRETO NESTE MILESTONE**: GBE power-gated, sky2 probe falha `unsupported chip type 0x0` — ver ICC_GBE_TEST_LOG.md
- [ ] IP estático / Netconsole — dependem de eth0 ativo

### ✅ Storage
- [x] SATA (Baikal AHCI) - boot de HDD/SSD externo
- [x] USB 3.0 (xHCI) - pendrives, HDDs
- [x] SD/MMC (Baikal controller)

### ✅ Áudio
- [x] HDMI Audio (snd_hda_intel, device 1002:9921)
- [x] ALSA funcional

### ✅ Gráficos / Mesa (Xorg + OpenGL)
- [x] xorg-server 21.1.24 + xf86-video-amdgpu-ps4 25.0.0 instalados
- [x] **Mesa 20.0.8 + LLVM 9.0.1** (custom tarball noob404) — compatível com kernel 5.4/DRM 3.35.0
- [x] **glxgears funcional** — 60 FPS @ 1080p60 (VSync), direct rendering: Yes
- [x] GPU detectada: **AMD DG1501SML87LB (LIVERPOOL/Gladius, PCI 0x1002:0x9924)**
- [x] xorg.conf configurado em `/etc/X11/xorg.conf.d/10-amdgpu.conf`
- [x] Custom Mesa em `/home/noob404/mesa` via LD_LIBRARY_PATH

#### Repositório Mesa PS4 (DionKill) — usa Mesa 26.x git, precisa kernel 5.15+
```bash
# Adicionar em /etc/pacman.conf:
[ps4-video]
SigLevel = Optional
Server = https://dionkill.github.io/ps4-video-archlinux/repo/

# Instalar:
pacman -Syy
pacman -S mesa-ps4 libdrm-ps4 xf86-video-amdgpu-ps4 mesa-utils
```

#### Solução FUNCIONAL para kernel 5.4 (Baikal) — Mesa 20.0.8 custom
```bash
# Extrair tarball (195MB) do noob404:
tar xf custom-mesa-arch-v1-ps4linux.tar.xz -C /home/noob404/

# Script de ativação (mesa.sh):
MESA=/home/noob404/mesa
export LD_LIBRARY_PATH=$MESA/lib64:$MESA/lib:$LD_LIBRARY_PATH
export LIBGL_DRIVERS_PATH=$MESA/lib64/dri:$MESA/lib/dri
export VK_ICD_FILENAMES=$MESA/share/vulkan/icd.d/radeon_icd.x86_64.json:$MESA/share/vulkan/icd.d/radeon_icd.x86.json

# Iniciar X COM variáveis do Mesa customizado:
LD_LIBRARY_PATH=$MESA/lib64:$MESA/lib \
LIBGL_DRIVERS_PATH=$MESA/lib64/dri:$MESA/lib/dri \
xinit -- :0 vt1
```

#### Repositórios Alternativos (documentação)
| Fonte | Mesa Version | Kernel Mínimo | Status |
|-------|-------------|---------------|--------|
| **noob404 custom tarball** | **20.0.8** | **5.4 (DRM 3.35)** | ✅ **FUNCIONA** |
| DionKill ps4-video-archlinux | 26.x git | 5.15+ (DRM 3.42) | ❌ Incompatível |
| AUR centi07 | 26.x git | 5.15+ | ❌ Incompatível |
| Hakkuraifu PS4Linux-ArchDrivers | 22.0.3 | ? | Offline |
| whitehax0r ArchLinux-PS4-Drivers | 22.x | ? | Antigo (2022) |

#### ⚠️ Nota crítica de compatibilidade
Mesa 22+ exige **DRM 3.42.0** (kernel 5.15+). Kernel 5.4.247 (Baikal) tem **DRM 3.35.0** → **apenas Mesa ≤21.x funciona**. O tarball noob404 (Mesa 20.0.8 + LLVM 9.0.1) é a solução atual.

### ✅ RTC/Time
- [x] Hook initramfs `hooks/early/set-time-from-cmdline` lê `time=` do payload
- [x] Payload injeta timestamp Unix automaticamente
- [x] `date -s @TIMESTAMP` + `hwclock -w -u` no early boot

### ✅ VRAM Control
- [x] `vram.txt` na partição FAT32 (default 1024 = 1GB)
- [x] Payload lê e passa via kexec
- [x] Valores suportados: 32, 64, 128, 256, 512, 1024, 2048, 3072, 4096 (MB)

### ✅ Build System
- [x] `00-build-kernel.sh` - compila kernel neocine com patches (MediaTek, sky2, gcc16)
- [x] `01-build-image.sh` - cria rootfs Arch com:
  - systemd 258.1 (downgrade fixo)
  - EDID firmware copy
  - RTC time hook
  - VRAM.txt copy
  - SSH, WiFi, netconsole, debug tools
- [x] `02-burn-image.sh` - grava HD (FAT32 boot + ext4 root)
- [x] `rebuild-initramfs.sh` - reconstrói initramfs com hooks

---

## Problemas Conhecidos / Workarounds

| Problema | Workaround |
|----------|------------|
| TV desligada = sem vídeo | `drm.edid_firmware=edid/ps4_tv_edid.bin` (implementado) |
| DP link training falha | ps4_bridge ignora e força enable (normal) |
| DPM desligado | `radeon.dpm=0 amdgpu.dpm=0` (estável, clocks fixos) |
| UART console conflita com vídeo | **NÃO USAR** `console=uart8250...` junto com vídeo |
| EDID vazio no sysfs | Usar `/sys/bus/i2c/devices/3-0050/eeprom` (raw) |
| systemd > 258 quebra boot | Downgrade fixo para 258.1-1 |

---

## Arquivos de Referência

```
/mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2/
├── boot_referencia/
│   ├── bzImage              # Kernel compilado
│   ├── initramfs.cpio.gz    # Initramfs com hooks
│   ├── bootargs.txt         # Kernel cmdline
│   ├── vram.txt             # 1024 (1GB VRAM)
│   └── bootlog.txt          # Vazio (payload escreve)
├── ps4_tv_edid.bin          # EDID backup (256 bytes)
├── 00-build-kernel.sh
├── 01-build-image.sh
├── 02-burn-image.sh
├── rebuild-initramfs.sh
├── neocine.config           # Kernel config
├── PS4_HARDWARE_DOCS.md     # Documentação completa hardware
└── MILESTONE_2026-07-14.md  # Este arquivo
```

---

## Próximos Passos (Roadmap)

1. **UART Console** - testar isolado (sem vídeo) com cabo JST-SH 3.3V
2. **WiFi** - MediaTek MT7668 (driver mt76x8, fw mt7668pr2h.bin)
3. **Bluetooth** - mesmo chip, precisa fw + bluez
4. **Power Management** - reativar DPM com testes de estabilidade
5. ~~**Mesa/Vulkan**~~ ✅ Mesa customizado via DionKill's repo (Mesa estável + patches PS4)
6. **Sleep/Suspend** - testar com ps4_bridge
7. **Mainline kernel** - migrar para 6.x quando suporte PS4 maduro

---

## Comandos Úteis

```bash
# SSH
ssh root@192.168.6.128  # senha: ps4

# Ver logs kernel remoto (netconsole)
nc -u -l -p 6666

# Status display
cat /sys/class/drm/card0-HDMI-A-1/status
cat /sys/class/drm/card0-HDMI-A-1/enabled

# EDID raw
cat /sys/bus/i2c/devices/3-0050/eeprom | xxd

# VRAM atual
cat /sys/kernel/debug/dri/0/amdgpu_vram_mm 2>/dev/null

# Rebuild initramfs após mudanças
./rebuild-initramfs.sh
sudo ./02-burn-image.sh /dev/sda
```

---

**Data**: 2026-07-14  
**Autor**: Anderson  
**PS4**: Baikal (CUH-2xxx), FW 9.00+  
**Status**: ✅ BOOTANDO + SSH + VÍDEO + REDE + ÁUDIO + RTC + XORG + MESA + GLXGEARS
