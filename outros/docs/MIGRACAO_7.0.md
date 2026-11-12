# Kernel 7.0 Strawberry Baikal — Guia de Build e Deploy

> **Nota:** Este projeto é focado exclusivamente no **kernel 7.0 Strawberry Baikal**.
> Não há mais suporte nem build do kernel 5.4 (neocine) neste repositório. Todos os
> caminhos e procedimentos abaixo referem-se apenas à frente 1 (kernel 7.0).

---

## Scripts Oficiais

| Script | Função |
|--------|--------|
| `kernel/00-build-kernel-7.0.sh <TAG>` | Compila kernel 7.0 (ThinLTO, General, Baikal). Gera `distro/boot_referencia/bzImage-7.0-<TAG>` + `config-7.0-<TAG>` + snapshot em `kernel/snapshots/`. |
| `distro/01-build-image-7.0.sh <TAG>` | Cria rootfs Arch + initramfs com módulos 7.0. Gera `distro/boot_referencia/initramfs-7.0-<TAG>.cpio.gz` e `bootargs-7.0-<TAG>.txt`. |
| `distro/rebuild-initramfs-7.0.sh <TAG>` | Reconstrói initramfs após mudanças de hooks (detecta KVER dentro do rootfs montado). |
| `distro/deploy-boot-7.0.sh <TAG>` | Troca só os arquivos de boot (sda1) no HD já particionado, mantém o rootfs intacto. |
| `distro/02-burn-image-7.0.sh /dev/sdX "" <TAG>` | Particiona + grava tudo (label `psxitarch` obrigatório). Use para refazer rootfs do zero. |

---

## Fluxo de Build (SEMPRE pelos scripts oficiais)

```bash
# Frente 1 — kernel (em kernel/)
cd kernel
sudo ./00-build-kernel-7.0.sh 20261112-sky2builtin

# Frente 2 — distro (em distro/)
cd ../distro
sudo ./01-build-image-7.0.sh 20261112-sky2builtin   # rootfs + initramfs (host Arch)
# ou, em host sem Arch:
./scripts/build-image-docker.sh 20261112-sky2builtin  # mesmo script, dentro de archlinux:latest

# Deploy (HD USB do PS4 plugado neste PC)
sudo ./deploy-boot-7.0.sh 20261112-sky2builtin   # só o boot, mantém rootfs
```

---

## Pré-requisitos da Máquina de Build

```bash
# Ubuntu 22.04+ / Debian 12 / Arch
apt install -y build-essential clang lld llvm \
  libssl-dev bc flex bison libelf-dev dwarves git \
  python3 pahole cpio zstd
```

Host sem Arch? Use `distro/scripts/build-image-docker.sh` (roda o mesmo
`01-build-image-7.0.sh` dentro de `archlinux:latest`).

---

## Firmware Necessário (em `kernel/kernel_build_7.0/extra_firmware/`)

```
extra_firmware/
├── mrvl/
│   ├── sd8897_uapsta.bin      # Wi-Fi/Bluetooth Marvell (Aeolia/Belize)
│   └── sd8797_uapsta.bin      # ORBIS CUSTOM — obtido do PS4 (feeRnt/ps4-linux-initramfs)
├── mediatek/
│   ├── mt7668pr2h.bin         # MT7668 Wi-Fi/BT (Baikal)
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
    └── gladius_sdma1.bin      # Firmware GPU Gladius REAL (dump do console, não liverpool)
```

**Importante:** O firmware GPU Gladius deve ser o **real extraído do console**
(ver `outros/rea/firmware_gladius_real/`). Cópias do `liverpool_*.bin` **não**
funcionam para o GFX/CP do Gladius (ver `outros/docs/TENTATIVAS_7.0.md` item 4).

---

## Layout da Partição BOOT (FAT32, 200 MB)

Após `deploy-boot-7.0.sh <TAG>`:

```
/mnt/boot/
├── bzImage              # Kernel 7.0 ativo (cópia de bzImage-7.0-<TAG>)
├── initramfs.cpio.gz    # Initramfs 7.0 ativo
├── bootargs.txt         # Cmdline 7.0 ativo
├── vram.txt             # "1024" (MB)
├── bootlog.txt          # Vazio (payload escreve)
└── active-tag.txt       # Nome da tag ativa (ex: 20261112-sky2builtin)
```

---

## Kernel Cmdline 7.0 (`bootargs-7.0-<TAG>.txt`)

```bash
panic=0 clocksource=tsc consoleblank=0 net.ifnames=0 radeon.dpm=0 amdgpu.dpm=0 drm.debug=0x06
earlycon=uart8250,mmio32,0xC890E000 console=uart8250,mmio32,0xC890E000 console=tty0 keep_bootcon
earlyprintk=efi,keep loglevel=8 root=LABEL=psxitarch rw rootwait
systemd.unified_cgroup_hierarchy=0 systemd.legacy_systemd_cgroup_controller=yes audit=0
amdgpu.audio=1 usbcore.autosuspend=-1 video=HDMI-A-1:1920x1080@60 mitigations=off zswap.enabled=1
log_buf_len=4M libata.force=1.00:3.0Gbps,noncq ahci.mobile_lpm_policy=1
netconsole=@192.168.0.2/eth0,6666@192.168.0.1/ff:ff:ff:ff:ff:ff
```

**Convenções validadas ao vivo:**
- `root=LABEL=psxitarch` + `rootwait` (nunca `rootdelay=N` nem outro label — lição #7)
- `earlycon=uart8250,mmio32,0xC890E000` + `console=uart8250,mmio32,0xC890E000` (nunca `console=ttyS0`)
- `console=tty0` mantido para vídeo HDMI

---

## Pós-Instalação no PS4 (SSH)

```bash
sshpass -p ps4 ssh root@192.168.6.128   # WiFi (wlan0, admin)
# ou, quando eth0 estiver funcional:
ping -I eth0 -c 3 192.168.0.1           # rede cabeada sob teste (192.168.0.0/24)

# Swap (essencial - 8 GB RAM unificada)
fallocate -l 8G /swapfile && chmod 600 /swapfile
mkswap /swapfile && swapon /swapfile

# Verificar Ethernet Baikal (mts.ko)
dmesg | grep -i mts
ip link show eth0

# Verificar GPU Gladius (amdgpu)
dmesg | grep -i amdgpu
glxinfo | grep OpenGL   # se Mesa patchado Gladius/Liverpool estiver presente

# Verificar SATA interno (Toshiba MQ04ABF100)
dmesg | grep -i 'ata1\|disable'
```

---

## Regras Críticas (ver AGENTS.md)

1. **Nunca rodar `make bzImage` direto** — sempre via `kernel/00-build-kernel-7.0.sh`.
2. **Nunca montar diretamente em `/mnt`** — sempre subdiretório dedicado (`/mnt/ps4_burn_7.0`, `/mnt/ps4_rootfs_7.0`, etc.).
3. **Todo `.sh` deve ser executável** (`chmod +x`, modo `100755` no git).
4. **Todo patch do kernel deve ser `git apply --check` antes de aplicar** — nunca fallback silencioso.
5. **Label do rootfs é obrigatória:** `psxitarch` (hardcoded no initramfs).
6. **Build em ext4** — nunca em `/mnt/t` (NTFS).
7. **Bootargs com UART MMIO + `rootwait`** — nunca `console=ttyS0` nem `rootdelay=N`.

---

## Referências

- [`../../AGENTS.md`](../../AGENTS.md) — fonte única de regras e procedimentos
- [`../../kernel/00-build-kernel-7.0.sh`](../../kernel/00-build-kernel-7.0.sh) — script oficial de build
- [`../../distro/README.md`](../../distro/README.md) — frente 2 (distro Arch)
- [`../../outros/consolidado/LICOES_APRENDIDAS.md`](../../outros/consolidado/LICOES_APRENDIDAS.md) — lições aprendidas
