#!/bin/bash
# 01-build-image-7.0.sh — Cria rootfs Arch + initramfs para kernel 7.0 Strawberry Baikal
set -euo pipefail

[ "$EUID" -eq 0 ] || { echo "Execute com sudo"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="/mnt/hdauxiliar/temp/arch_build_7.0"
KERNEL_VERSION_FILE="$SCRIPT_DIR/boot_referencia/artifact_name-7.0.txt"
BOOT_DIR="$SCRIPT_DIR/boot_referencia"

ROOTFS_DIR="$BUILD_ROOT/rootfs"

# Robust cleanup function - handles "device or resource busy" by unmounting first
cleanup() {
  set +e
  if [ -d "$BUILD_ROOT" ]; then
    # Unmount all mounts under BUILD_ROOT recursively (deepest first)
    findmnt -R "$BUILD_ROOT" -n -o TARGET 2>/dev/null | sort -r | while read -r mp; do
      mountpoint -q "$mp" && umount -l "$mp" 2>/dev/null || true
    done
  fi
  # Also clean standard chroot mounts
  for mp in proc sys dev run; do
    mountpoint -q "$ROOTFS_DIR/$mp" 2>/dev/null && umount -R "$ROOTFS_DIR/$mp" 2>/dev/null || true
  done
  # Unmount pacman cache
  mountpoint -q "$ROOTFS_DIR/var/cache/pacman/pkg" 2>/dev/null && umount -l "$ROOTFS_DIR/var/cache/pacman/pkg" 2>/dev/null || true
  sleep 0.5
  set -e
}
trap cleanup EXIT INT TERM

# Determinar versão do kernel 7.0 (UTS_RELEASE real)
# O UTS_RELEASE é a string exata usada por modules_install e mkinitcpio
KERNEL_BUILD_DIR="/mnt/hdauxiliar/temp/kernel_build_7.0"
UTS_RELEASE_FILE="$KERNEL_BUILD_DIR/include/generated/utsrelease.h"
if [ -f "$UTS_RELEASE_FILE" ]; then
  KVER_FULL=$(grep -oP '"\K[^"]+' "$UTS_RELEASE_FILE")
elif [ -f "$BOOT_DIR/config-7.0" ]; then
  KVER=$(grep "^KERNEL_VERSION" "$BOOT_DIR/config-7.0" | cut -d= -f2 2>/dev/null || echo "7.0.8")
  LOCALVERSION=$(grep "^CONFIG_LOCALVERSION=" "$BOOT_DIR/config-7.0" | sed 's/^CONFIG_LOCALVERSION="//' | sed 's/"$//' 2>/dev/null)
  KVER_FULL="${KVER}${LOCALVERSION}"
else
  echo "ERRO: Não foi possível determinar versão do kernel 7.0"
  exit 1
fi

echo "=== Kernel version: $KVER_FULL ==="

MODULES_DIR="$ROOTFS_DIR/lib/modules/$KVER_FULL"
OUTPUT_TAR="$SCRIPT_DIR/arch_minimal_v2-7.0.tar"

echo "=== Preparando diretórios ==="
cleanup
rm -rf "$BUILD_ROOT"
mkdir -p "$ROOTFS_DIR" "$BOOT_DIR"

echo "=== Bootstrap Arch Linux base ==="
pacstrap -c "$ROOTFS_DIR" base linux-api-headers

# Montar cache do pacman no chroot
mkdir -p "$ROOTFS_DIR/var/cache/pacman/pkg"
mount --bind /var/cache/pacman/pkg "$ROOTFS_DIR/var/cache/pacman/pkg"

echo "=== Configurando pacman.conf (systemd 258 pin, DisableSandbox) ==="
cat > "$ROOTFS_DIR/etc/pacman.conf" << 'PACMANEOF'
[options]
HoldPkg     = pacman glibc
Architecture = auto
Color
CheckSpace
ParallelDownloads = 5
DisableSandbox
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional
IgnorePkg   = linux linux-headers mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
PACMANEOF

echo "=== Instalando pacotes essenciais ==="
# Pacotes gráficos (xorg/mesa/vulkan/openbox) ficam disponíveis na imagem,
# mas NÃO sobem sozinhos: nenhum display manager é instalado/habilitado e
# systemctl set-default abaixo força multi-user.target (boot em TTY puro).
# Rodar Xorg/openbox fica manual (startx) até a distro estar completa.
PKGS=(
  base
  linux-firmware
  openssh
  sudo
  vim
  nano
  htop
  iotop
  iftop
  nethogs
  net-tools
  iproute2
  dhcpcd
  wpa_supplicant
  wireless-regdb
  iw
  bluez
  bluez-utils
  usbutils
  pciutils
  lsof
  strace
  perf
  dmidecode
  smartmontools
  nvme-cli
  mdadm
  lvm2
  cryptsetup
  btrfs-progs
  dosfstools
  e2fsprogs
  xfsprogs
  f2fs-tools
  ntfs-3g
  exfatprogs
  samba
  nfs-utils
  cronie
  systemd-sysvcompat
  python3
  python-pip
  git
  curl
  wget
  rsync
  unzip
  tar
  gzip
  xz
  zstd
  jq
  ccache
  distcc
  meson
  ninja
  pkgconf
  mkinitcpio
  mesa
  lib32-mesa
  vulkan-radeon
  lib32-vulkan-radeon
  vulkan-tools
  mesa-utils
  xorg-server
  xorg-xinit
  openbox
)

# Instalar usando pacman do host (evita problema de mountpoint no chroot)
HOST_PACMAN_CONF="$ROOTFS_DIR/etc/pacman.conf"
HOST_PACMAN_CACHE="/var/cache/pacman/pkg"
mkdir -p "$ROOTFS_DIR/var/lib/pacman/sync"

# Montar /proc necessário para hooks pós-transação do pacman (systemd-tmpfiles etc.)
mount -t proc proc "$ROOTFS_DIR/proc"

pacman --root "$ROOTFS_DIR" --config "$HOST_PACMAN_CONF" --cachedir "$HOST_PACMAN_CACHE" -Sy --noconfirm "${PKGS[@]}"

umount "$ROOTFS_DIR/proc"

echo "=== Configurando sistema ==="

# Timezone
ln -sf /usr/share/zoneinfo/America/Sao_Paulo "$ROOTFS_DIR/etc/localtime"

# Locale (paridade com o rootfs 5.4 - en_US + pt_BR)
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$ROOTFS_DIR/etc/locale.gen"
sed -i 's/^#pt_BR.UTF-8 UTF-8/pt_BR.UTF-8 UTF-8/' "$ROOTFS_DIR/etc/locale.gen"
arch-chroot "$ROOTFS_DIR" locale-gen
echo "LANG=pt_BR.UTF-8" > "$ROOTFS_DIR/etc/locale.conf"
echo "KEYMAP=br-abnt2" > "$ROOTFS_DIR/etc/vconsole.conf"

# Hostname
echo "ps4-baikal" > "$ROOTFS_DIR/etc/hostname"

# Hosts
cat > "$ROOTFS_DIR/etc/hosts" << 'HOSTSEOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   ps4-baikal.localdomain ps4-baikal
HOSTSEOF

# Rede estática (systemd-networkd)
mkdir -p "$ROOTFS_DIR/etc/systemd/network"
cat > "$ROOTFS_DIR/etc/systemd/network/20-ethernet.network" << 'NETEOF'
[Match]
Name=eth0

[Network]
Address=192.168.0.2/24
Gateway=192.168.0.1
DNS=192.168.0.1
DNS=8.8.8.8
NETEOF

# Auto-carregamento do driver Ethernet Baikal (mts.ko) no boot com stage=4
mkdir -p "$ROOTFS_DIR/etc/modules-load.d"
echo "mts" > "$ROOTFS_DIR/etc/modules-load.d/mts.conf"
mkdir -p "$ROOTFS_DIR/etc/modprobe.d"
echo "options mts stage=4" > "$ROOTFS_DIR/etc/modprobe.d/mts.conf"

# SSH (config permissiva, paridade com o rootfs 5.4 que funciona)
if [ -f "$ROOTFS_DIR/etc/ssh/sshd_config" ]; then
  mv "$ROOTFS_DIR/etc/ssh/sshd_config" "$ROOTFS_DIR/etc/ssh/sshd_config.bak"
  cat > "$ROOTFS_DIR/etc/ssh/sshd_config" << 'SSHEOF'
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords yes
StrictModes no
SSHEOF
  cat "$ROOTFS_DIR/etc/ssh/sshd_config.bak" >> "$ROOTFS_DIR/etc/ssh/sshd_config"
  rm -f "$ROOTFS_DIR/etc/ssh/sshd_config.bak"
fi
arch-chroot "$ROOTFS_DIR" ssh-keygen -A
ln -sf /usr/lib/systemd/system/sshd.service "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/sshd.service"

# Garantir que o boot padrão é multi-user.target (console text mode puro, sem interface gráfica)
echo "=== Configurando boot padrão para multi-user.target (TTY console) ==="
arch-chroot "$ROOTFS_DIR" systemctl set-default multi-user.target
echo "Boot padrão definido para multi-user.target (console text mode TTY)"

# SSH automático — script que monta rootfs e inicia sshd via chroot
echo "=== Instalando SSH automático ==="
mkdir -p "$ROOTFS_DIR/usr/local/bin"
cp "$SCRIPT_DIR/ssh-startup.sh" "$ROOTFS_DIR/usr/local/bin/ssh-startup.sh"
chmod 755 "$ROOTFS_DIR/usr/local/bin/ssh-startup.sh"
mkdir -p "$ROOTFS_DIR/etc/systemd/system"
cp "$SCRIPT_DIR/ssh-auto-startup.service" "$ROOTFS_DIR/etc/systemd/system/ssh-auto-startup.service"
ln -sf /etc/systemd/system/ssh-auto-startup.service \
  "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/ssh-auto-startup.service"

# NOTA: NÃO precisa de serviço de netconsole aqui. CONFIG_NETCONSOLE=y é
# builtin no kernel 7.0 (não módulo) e se ativa sozinho lendo o parâmetro
# netconsole= do cmdline no early boot - não depende de systemd/userspace.
# (Um serviço rodando "nc -u -l -p 6666" DENTRO do PS4 não tem efeito algum
# sobre o netconsole do kernel - foi removido daqui por ser um resquício sem
# função, mantido só como nota para não recriarmos o mesmo engano.)

# Reduzir ruído de log (paridade com o rootfs 5.4 que funciona)
mkdir -p "$ROOTFS_DIR/etc/sysctl.d"
echo "kernel.printk = 3 4 1 7" > "$ROOTFS_DIR/etc/sysctl.d/30-loglevel.conf"
grep -q "^Audit=" "$ROOTFS_DIR/etc/systemd/journald.conf" 2>/dev/null \
  || sed -i '/^\[Journal\]/a Audit=no' "$ROOTFS_DIR/etc/systemd/journald.conf"

# Senha root
echo "root:ps4" | arch-chroot "$ROOTFS_DIR" chpasswd

# Usuario ps4 (paridade com o rootfs 5.4 que funciona)
arch-chroot "$ROOTFS_DIR" useradd -m -G wheel -s /bin/bash ps4 2>/dev/null || true
echo "ps4:ps4" | arch-chroot "$ROOTFS_DIR" chpasswd

# Sudo sem senha para root
echo "root ALL=(ALL) NOPASSWD: ALL" > "$ROOTFS_DIR/etc/sudoers.d/root-nopasswd"
chmod 440 "$ROOTFS_DIR/etc/sudoers.d/root-nopasswd"

mkdir -p "$ROOTFS_DIR/etc/sudoers.d"
echo "%wheel ALL=(ALL:ALL) ALL" > "$ROOTFS_DIR/etc/sudoers.d/wheel"
chmod 440 "$ROOTFS_DIR/etc/sudoers.d/wheel"

# WiFi (paridade com o rootfs 5.4 que funciona - mesmo SSID/senha)
echo "=== Configurando wpa_supplicant para WiFi ==="
mkdir -p "$ROOTFS_DIR/etc/wpa_supplicant"
cat > "$ROOTFS_DIR/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" << 'WPAEOF'
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel
update_config=1
country=BR

network={
	ssid="prfelicidade_5G"
	psk="9911121314"
}
WPAEOF
chmod 600 "$ROOTFS_DIR/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
mkdir -p "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/wpa_supplicant@.service \
  "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service"
mkdir -p "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/dhcpcd.service \
  "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/dhcpcd.service"
# eth0 já é estático via systemd-networkd (20-ethernet.network acima) -
# dhcpcd só deve gerenciar wlan0, senão os dois disputam a interface eth0
echo "denyinterfaces eth0" >> "$ROOTFS_DIR/etc/dhcpcd.conf"

# CORREÇÃO 2026-07-23: Habilitar systemd-networkd para carregar config de rede estática (eth0)
mkdir -p "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/systemd-networkd.service \
  "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"

# (Opcional) Habilitar systemd-resolved para DNS via systemd-networkd
ln -sf /usr/lib/systemd/system/systemd-resolved.service \
  "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/systemd-resolved.service"

echo "=== Instalando módulos do kernel 7.0 ==="
# Copiar módulos compilados do kernel build
if [ -d "$KERNEL_BUILD_DIR" ]; then
  echo "Copiando módulos pré-compilados de $KERNEL_BUILD_DIR..."
  make -C "$KERNEL_BUILD_DIR" INSTALL_MOD_PATH="$ROOTFS_DIR" INSTALL_MOD_STRIP=1 modules_install
else
  echo "AVISO: Diretório de build do kernel não encontrado. Módulos não instalados."
fi

# Copiar opcionalmente o mts.ko compilado separadamente (em drivers_mts/build/mts.ko)
MTS_LOCAL_KO="$SCRIPT_DIR/../../drivers_mts/build/mts.ko"
if [ -f "$MTS_LOCAL_KO" ]; then
  MTS_DEST_DIR="$MODULES_DIR/kernel/drivers/net/ethernet/sony"
  echo "=== Sobrescrevendo/Garantindo mts.ko local mais recente de drivers_mts/build/mts.ko ==="
  mkdir -p "$MTS_DEST_DIR"
  cp -v "$MTS_LOCAL_KO" "$MTS_DEST_DIR/mts.ko"
  echo "Executando depmod para atualizar dependências de módulos..."
  arch-chroot "$ROOTFS_DIR" depmod -a "$KVER_FULL"
else
  echo "Aviso: Módulo local mts.ko não encontrado em $MTS_LOCAL_KO. Mantendo versão padrão."
fi


# Verificar módulos essenciais para Baikal
# Formato: "nome_modulo:config_option"
# O script verifica se existe como .ko OU se está built-in (=y) no .config
# NOTA: Ethernet Baikal é sky2 (built-in), NÃO stmmac/dwmac - já confirmado
# via dmesg real do console. stmmac não existe neste kernel/config.
REQUIRED_MODULES=(
  "mt76-sdio:CONFIG_MT76_SDIO"
  "btmtksdio:CONFIG_BT_MTKSDIO"
  "amdgpu:CONFIG_DRM_AMDGPU"
  "snd-hda-intel:CONFIG_SND_HDA_INTEL"
  "sky2:CONFIG_SKY2"
)
# Drivers built-in (=y) no kernel 7.0 - não precisam de .ko no initramfs
BUILTIN_DRIVERS=(
  "CONFIG_SKY2"
  "CONFIG_MT76_SDIO"
  "CONFIG_USB_XHCI_HCD"
  "CONFIG_USB_XHCI_AEOLIA"
  "CONFIG_SATA_AHCI"
  "CONFIG_MMC_SDHCI"
  "CONFIG_MMC_SDHCI_PCI"
)

KERNEL_CONFIG="$KERNEL_BUILD_DIR/.config"
echo "=== Verificando módulos essenciais ==="
for entry in "${REQUIRED_MODULES[@]}"; do
  mod="${entry%%:*}"
  cfg="${entry##*:}"
  mod_file=$(find "$MODULES_DIR" -name "${mod}.ko*" 2>/dev/null | head -1 || true)
  cfg_val=$(grep "^${cfg}=" "$KERNEL_CONFIG" 2>/dev/null | head -1 || true)
  if [ -n "$mod_file" ]; then
    echo "  OK (modulo): $mod -> $(basename "$mod_file")"
  elif [ -n "$cfg_val" ]; then
    echo "  OK (built-in): $mod -> $cfg_val"
  else
    echo "  FALTANDO: $mod"
  fi
done
echo "=== Verificando drivers built-in ==="
for cfg in "${BUILTIN_DRIVERS[@]}"; do
  cfg_val=$(grep "^${cfg}=" "$KERNEL_CONFIG" 2>/dev/null | head -1 || true)
  if [ -n "$cfg_val" ]; then
    echo "  OK (built-in): $cfg_val"
  else
    echo "  FALTANDO: $cfg"
  fi
done

echo "=== Criando initramfs (mkinitcpio) ==="
# Configurar mkinitcpio para kernel 7.0 (sem autodetect para evitar remover módulos no chroot)
cat > "$ROOTFS_DIR/etc/mkinitcpio.conf" << 'MKEOF'
MODULES=(ext4 ahci sd_mod btmtksdio amdgpu snd-hda-intel sky2 usbhid uas usb_storage)
BINARIES=()
FILES=(/lib/firmware/edid/ps4_tv_edid.bin)
HOOKS=(base udev modconf block filesystems keyboard fsck)
COMPRESSION="gzip"
MKEOF

# Copiar EDID firmware
mkdir -p "$ROOTFS_DIR/lib/firmware/edid"
cp "$SCRIPT_DIR/ps4_tv_edid.bin" "$ROOTFS_DIR/lib/firmware/edid/ps4_tv_edid.bin"

# Copiar firmwares genuínos Gladius GPU (AMD PS4 Pro)
echo "=== Copiando firmwares genuínos AMD Gladius GPU ==="
mkdir -p "$ROOTFS_DIR/lib/firmware/amdgpu"
if [ -d "$SCRIPT_DIR/firmware_gpu/amdgpu" ]; then
  cp -v "$SCRIPT_DIR/firmware_gpu/amdgpu"/gladius_*.bin "$ROOTFS_DIR/lib/firmware/amdgpu/" || true
fi

# Copiar firmwares MediaTek MT7668 (WiFi/BT Baikal)
echo "=== Copiando firmwares MediaTek MT7668 (WiFi/BT) ==="
mkdir -p "$ROOTFS_DIR/lib/firmware/mediatek"
if [ -d "$SCRIPT_DIR/firmware_wifi/mediatek" ]; then
  cp -v "$SCRIPT_DIR/firmware_wifi/mediatek"/* "$ROOTFS_DIR/lib/firmware/mediatek/" || true
fi
if [ -f "$KERNEL_BUILD_DIR/extra_firmware/WIFI_RAM_CODE_MT7668.bin" ]; then
  cp -v "$KERNEL_BUILD_DIR/extra_firmware/WIFI_RAM_CODE_MT7668.bin" "$ROOTFS_DIR/lib/firmware/mediatek/" || true
fi

# Hook custom para time= do payload
mkdir -p "$ROOTFS_DIR/etc/initcpio/install"
cat > "$ROOTFS_DIR/etc/initcpio/install/set-time-from-cmdline" << 'HOOKEOF'
#!/bin/bash
build() {
  add_runscript
}
HOOKEOF

cat > "$ROOTFS_DIR/etc/initcpio/hooks/set-time-from-cmdline" << 'HOOKEOF'
#!/bin/bash
run_hook() {
  for param in $(cat /proc/cmdline); do
    case "${param}" in
      time=*)
        TIMESTAMP="${param#time=}"
        if [ -n "${TIMESTAMP}" ] && [ "${TIMESTAMP}" -gt 0 ] 2>/dev/null; then
          date -s "@${TIMESTAMP}" || true
          hwclock -w -u || true
        fi
        ;;
    esac
  done
}
HOOKEOF

chmod +x "$ROOTFS_DIR/etc/initcpio/hooks/set-time-from-cmdline"

# Adicionar hook no mkinitcpio.conf
sed -i 's/HOOKS=(base /HOOKS=(base set-time-from-cmdline /' "$ROOTFS_DIR/etc/mkinitcpio.conf"

# Gerar initramfs
cp "$BOOT_DIR/bzImage-7.0" "$ROOTFS_DIR/boot/vmlinuz-$KVER_FULL"
arch-chroot "$ROOTFS_DIR" mkinitcpio -k "$KVER_FULL" -g "/boot/initramfs-$KVER_FULL.img"

echo "=== Usando initramfs recem-gerado (mkinitcpio, reflete o rootfs desta build) ==="
cp "$ROOTFS_DIR/boot/initramfs-$KVER_FULL.img" "$BOOT_DIR/initramfs-7.0.cpio.gz"

echo "=== Criando bootargs-7.0.txt ==="
cat > "$BOOT_DIR/bootargs-7.0.txt" << 'CMDLINEEOF'
panic=0 clocksource=tsc consoleblank=0 net.ifnames=0 radeon.dpm=0 amdgpu.dpm=0 drm.debug=0x06 console=tty0 earlyprintk=efi,keep loglevel=8 root=LABEL=psxitarch rw rootdelay=10 systemd.unified_cgroup_hierarchy=0 systemd.legacy_systemd_cgroup_controller=yes audit=0 amdgpu.audio=1 usbcore.autosuspend=-1 video=HDMI-A-1:1920x1080@60 mitigations=off zswap.enabled=1 log_buf_len=4M netconsole=@192.168.0.2/eth0,6666@192.168.0.1/ff:ff:ff:ff:ff:ff
CMDLINEEOF

echo "=== Copiando vram.txt ==="
if [ ! -f "$BOOT_DIR/vram.txt" ]; then
  echo "1024" > "$BOOT_DIR/vram.txt"
fi

echo "=== Criando tarball do rootfs ==="
tar -C "$ROOTFS_DIR" -cf "$OUTPUT_TAR" .

echo "=== Resumo ==="
echo "Kernel version: $KVER_FULL"
echo "Rootfs tarball: $OUTPUT_TAR"
echo "Initramfs: $BOOT_DIR/initramfs-7.0.cpio.gz"
echo "Bootargs: $BOOT_DIR/bootargs-7.0.txt"
echo "Config: $BOOT_DIR/config-7.0"
echo "bzImage: $BOOT_DIR/bzImage-7.0"
echo ""
echo "Próximo passo: sudo ./02-burn-image.sh /dev/sda"