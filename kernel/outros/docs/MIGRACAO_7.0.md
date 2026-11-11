# Migração 5.4 → 7.0 (Strawberry Baikal) - Guia Rápido

## Scripts Criados

| Script | Função |
|--------|--------|
| `00-build-kernel-7.0.sh` | Compila kernel 7.0 via `build.sh` (ThinLTO, General, Baikal) |
| `01-build-image-7.0.sh` | Cria rootfs Arch + initramfs com módulos 7.0 |
| `rebuild-initramfs-7.0.sh` | Reconstrói initramfs após mudanças de hooks |
| `02-burn-image.sh` | **Atualizado** - suporta 5.4 e 7.0 (auto-detect) |

---

## Fluxo de Build

```bash
# 1. Compilar kernel 7.0 (precisa LLVM/Clang 18+)
sudo ./00-build-kernel-7.0.sh

# 2. Criar rootfs + initramfs
sudo ./01-build-image-7.0.sh

# 3. Gravar no HD (auto-detecta 5.4 vs 7.0)
sudo ./02-burn-image.sh /dev/sda        # auto (prefere 7.0 se existir)
sudo ./02-burn-image.sh /dev/sda 7.0    # força 7.0
sudo ./02-burn-image.sh /dev/sda 5.4    # força 5.4
```

---

## Pré-requisitos Build Machine

```bash
# Ubuntu 22.04+ / Debian 12 / Arch
apt install -y build-essential clang-18 lld-18 llvm-18 \
  libssl-dev bc flex bison libelf-dev dwarves git \
  python3 pahole cpio zstd
```

---

## Firmware Necessário (em `extra_firmware/` do kernel source)

```
extra_firmware/
├── mrvl/
│   ├── sd8897_uapsta.bin      # Público (Belize WiFi) - auto-baixado
│   └── sd8797_uapsta.bin      # **ORBIS CUSTOM** - precisa obter do PS4
├── mediatek/
│   ├── mt7668pr2h.bin         # MT7668 WiFi/BT (Baikal)
│   ├── EEPROM_MT7668.bin
│   ├── EEPROM_MT7668_e1.bin
│   ├── mt7668_patch_e1_hdr.bin
│   ├── mt7668_patch_e2_hdr.bin
│   ├── TxPwrLimit_MT76x8.dat
│   ├── wifi.cfg
│   ├── WIFI_RAM_CODE2_SDIO_MT7668.bin
│   ├── WIFI_RAM_CODE2_USB_MT7668.bin
│   └── WIFI_RAM_CODE_MT7668.bin
└── amdgpu/
    ├── gladius_ce.bin
    ├── gladius_me.bin
    ├── gladius_mec.bin
    ├── gladius_mec2.bin
    ├── gladius_pfp.bin
    ├── gladius_rlc.bin
    ├── gladius_sdma.bin
    └── gladius_sdma1.bin
```

**✅ RESOLVIDO:** `sd8797_uapsta.bin` obtido do [feeRnt/ps4-linux-initramfs](https://github.com/feeRnt/ps4-linux-initramfs/tree/main/lib/firmware/mrvl) — Orbis custom (443 KB) confirmado, diferente do upstream (522 KB). Salvo em `extra_firmware/mrvl/`.

---

## Boot Partition Layout (FAT32 50MB)

```
/mnt/boot/
├── bzImage              # Kernel ativo (symlink ou copiado)
├── bzImage-5.4          # Kernel 5.4 (backup)
├── bzImage-7.0          # Kernel 7.0
├── initramfs.cpio.gz    # Initramfs ativo
├── initramfs-5.4.cpio.gz
├── initramfs-7.0.cpio.gz
├── bootargs.txt         # Cmdline ativa
├── bootargs-5.4.txt
├── bootargs-7.0.txt
├── vram.txt             # "1024" (MB)
└── bootlog.txt          # Vazio (payload escreve)
```

---

## Kernel Cmdline 7.0 (`bootargs-7.0.txt`)

```bash
panic=0 clocksource=tsc consoleblank=0 net.ifnames=0
radeon.dpm=0 amdgpu.dpm=0
console=ttyS0,115200n8 console=tty0
video=HDMI-A-1:1920x1080@60
drm.edid_firmware=edid/ps4_tv_edid.bin
quiet amdgpu.audio=1 usbcore.autosuspend=-1
amdgpu.gpu_recovery=1 mitigations=off zswap.enabled=1
systemd.unified_cgroup_hierarchy=0 systemd.legacy_systemd_cgroup_controller=yes
audit=0
netconsole=6665@192.168.0.2/eth0,6666@192.168.0.1/b4:45:06:6c:f6:4f
```

---

## Pós-Instalação no PS4 (SSH)

```bash
ssh root@192.168.6.128  # senha: ps4

# Swap (essencial - 8GB RAM unificada)
fallocate -l 8G /swapfile && chmod 600 /swapfile
mkswap /swapfile && swapon /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab
echo "vm.swappiness=90" >> /etc/sysctl.d/99-swappiness.conf

# Verificar Ethernet (stmmac - DWMAC1000)
ip link
ethtool eth0
dmesg | grep -i stmmac

# Verificar WiFi/BT (MT7668)
dmesg | grep -i mt76
rfkill list
bluetoothctl

# Verificar GPU
dmesg | grep -i amdgpu
glxinfo | grep OpenGL

# Testar DPM (opcional)
echo auto > /sys/class/drm/card0/device/power_dpm_force_performance_level
```

---

## Dual Boot 5.4 / 7.0

O `02-burn-image.sh` mantém ambos kernels na partição FAT32:
- Renomeia `bzImage` → `bzImage-5.4` ou `bzImage-7.0`
- Payload (PSFree/GoldHEN) lê `bootargs.txt` → troque o symlink ou renomeie antes do boot

---

## Troubleshooting

| Problema | Solução |
|----------|---------|
| `sd8797_uapsta.bin` missing | Já em `extra_firmware/mrvl/` — auto-detectado pelo build |
| Build OOM (FullLTO) | Usar ThinLTO (padrão no script) ou mais RAM |
| Ethernet não sobe | Verificar `CONFIG_STMMAC_PCI=y`, `dmesg \| grep stmmac` |
| WiFi não aparece | Verificar `mt7668pr2h.bin` em `extra_firmware/mediatek/` |
| Tela preta | Manter `drm.edid_firmware=` + testar `video=` sem `e` |
| systemd falha boot | 7.0 usa cgroup v2 nativo - não precisa pin systemd 258 |

---

## Referências

- Kernel 7.0: https://github.com/rmuxnet/linux/tree/baikal/7.0.8-Stable
- Build system: `build.sh` (Strawberry Builder)
- PS4 Linux Discord: https://discord.gg/QtcPmzHVVm
- Guia instalação: https://dionkill.github.io/ps4-linux-tutorial/