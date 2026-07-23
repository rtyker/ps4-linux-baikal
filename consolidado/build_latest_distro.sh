#!/bin/bash
# Build da Distro Consolidada PS4 - Arch Minimal + Kernel Strawberry 7.0 (Bleeding Edge)
# Uso: sudo ./build_latest_distro.sh [kernel_source]
#   kernel_source: "strawberry" (padrao), "neocine", ou caminho para bzImage
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Execute com sudo"
  exit 1
fi

BASE_TAR="${2:-../distros/arch_minimal/arch_minimal.tar}"
ROOTFS_DIR="/mnt/hdauxiliar/temp/rootfs"
OUTPUT_DIR="./distro_output"
OUTPUT_TAR="arch_ps4_consolidado.tar.xz"

# Funcao para garantir a desmontagem segura dos diretorios do host
cleanup() {
  umount "$ROOTFS_DIR/proc" 2>/dev/null || true
  umount "$ROOTFS_DIR/sys" 2>/dev/null || true
  umount "$ROOTFS_DIR/dev" 2>/dev/null || true
}
trap cleanup EXIT
KERNEL_SRC="${1:-strawberry}"

KERNEL_NEOCINE="../kernels/5.4.247-neocine/bzImage"
KERNEL_STRAWBERRY="../kernels/strawberry-7.0/bzImage"

CUSTOM_MESA_PKG="../distros/arch/mesa-ps4-22.0.3-1-x86_64.pkg.tar.zst"
CUSTOM_LIB32_MESA_PKG="../distros/arch/lib32-mesa-ps4-22.0.3-1-x86_64.pkg.tar.zst"

echo "=============================================="
echo " Distro Consolidada PS4"
echo " Kernel: $KERNEL_SRC"
echo "=============================================="

# ── Escolha do kernel ─────────────────────────────────────────────────
case "$KERNEL_SRC" in
  neocine)
    BZIMAGE="$KERNEL_NEOCINE"
    KERNEL_VER="5.4.247-neocine-1.1"
    ;;
  strawberry)
    BZIMAGE="$KERNEL_STRAWBERRY"
    KERNEL_VER="7.0.0-Strawberry-FullLTO"
    ;;
  *)
    BZIMAGE="$KERNEL_SRC"
    KERNEL_VER="custom"
    ;;
esac

if [ ! -f "$BZIMAGE" ]; then
  echo "ERRO: bzImage nao encontrado em $BZIMAGE"
  exit 1
fi

echo "Usando kernel: $(file "$BZIMAGE" | grep -o 'version [^,]*')"

# ── 1. Rootfs ─────────────────────────────────────────────────────────
echo ""
echo "[1/8] Extraindo rootfs base..."
# Garante a desmontagem de execucoes anteriores que falharam antes de limpar
cleanup
mkdir -p "$ROOTFS_DIR"
rm -rf "$ROOTFS_DIR"/*
tar -xvpf "$BASE_TAR" -C "$ROOTFS_DIR" --numeric-owner

# ── 2. Drivers customizados ───────────────────────────────────────────
echo ""
echo "[2/8] Copiando drivers Mesa customizados..."
if [ -f "$CUSTOM_MESA_PKG" ]; then
  cp "$CUSTOM_MESA_PKG" "$ROOTFS_DIR/root/"
  cp "$CUSTOM_LIB32_MESA_PKG" "$ROOTFS_DIR/root/"
else
  echo "  (Mesa custom nao encontrado - sera instalado via pacman)"
fi

# ── 3. Config pacman ──────────────────────────────────────────────────
echo ""
echo "[3/8] Configurando pacman.conf..."
sed -i '/^#IgnorePkg/a IgnorePkg   = linux linux-headers mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon llvm-libs lib32-llvm-libs systemd systemd-libs systemd-sysvcompat' "$ROOTFS_DIR/etc/pacman.conf" 2>/dev/null || true
sed -i 's/^#DisableSandbox/DisableSandbox/' "$ROOTFS_DIR/etc/pacman.conf" 2>/dev/null || true
grep -q "^DisableSandbox" "$ROOTFS_DIR/etc/pacman.conf" 2>/dev/null || sed -i '/^\[options\]/a DisableSandbox' "$ROOTFS_DIR/etc/pacman.conf" 2>/dev/null || true

# ── 4. Script de config chroot ────────────────────────────────────────
echo ""
echo "[4/8] Preparando script de configuracao..."
cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

cat << 'CHROOTEOF' > "$ROOTFS_DIR/setup.sh"
#!/bin/bash

# Fuso Horario
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# Locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "pt_BR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=pt_BR.UTF-8" > /etc/locale.conf
echo "KEYMAP=br-abnt2" > /etc/vconsole.conf

# Rede estatica 192.168.6.130 via NetworkManager
mkdir -p /etc/NetworkManager/system-connections
cat << 'NMEOF' > /etc/NetworkManager/system-connections/Wired.nmconnection
[connection]
id=Wired connection
type=ethernet

[ipv4]
address1=192.168.6.130/24,192.168.6.1
dns=8.8.8.8;
method=manual

[ipv6]
method=auto
NMEOF
chmod 600 /etc/NetworkManager/system-connections/Wired.nmconnection

# Ativa repo extra
sed -i 's/^#\[extra\]/\[extra\]/' /etc/pacman.conf 2>/dev/null || true
sed -i '/^\[extra\]/{n;s/^#Include/Include/}' /etc/pacman.conf 2>/dev/null || true

# Chaotic-AUR
pacman-key --init
pacman-key --populate archlinux
pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
pacman-key --lsign-key 3056513887B78AEB
pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' || true
pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' || true

cat << 'REPOEOF' >> /etc/pacman.conf

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
REPOEOF

# Atualiza repositorios
pacman -Syu --noconfirm || true

# Instala pacotes essenciais
pacman -S --noconfirm --needed \
  networkmanager dhcpcd iw wpa_supplicant sudo openssh nano vim \
  fastfetch htop procps-ng docker docker-compose python npm \
  linux-firmware mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon \
  mkinitcpio || true

# Instala Mesa custom se disponivel
if [ -f /root/mesa-ps4-22.0.3-1-x86_64.pkg.tar.zst ]; then
  pacman -U --noconfirm /root/mesa-ps4-22.0.3-1-x86_64.pkg.tar.zst /root/lib32-mesa-ps4-22.0.3-1-x86_64.pkg.tar.zst || true
fi

# Servico wlan estatico
cat << 'WLANEOF' > /etc/systemd/system/wlan-static.service
[Unit]
Description=Configura IP estatico na wlan0
After=network.target

[Service]
Type=oneshot
ExecStart=-/usr/bin/ip link set wlan0 up
ExecStart=-/usr/bin/ip addr add 192.168.6.130/24 dev wlan0
ExecStart=-/usr/bin/ip route add default via 192.168.6.1
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
WLANEOF

systemctl enable NetworkManager docker wlan-static.service 2>/dev/null || true

# Usuario ps4
useradd -m -G wheel,docker -s /bin/bash ps4 2>/dev/null || true
echo 'ps4:ps4' | chpasswd
echo 'root:ps4' | chpasswd

# Sudo sem senha para wheel
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers 2>/dev/null || true

# Swap 8GB
fallocate -l 8G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=8192 2>/dev/null
chmod 600 /swapfile
mkswap /swapfile
# Apenas registramos no fstab para ativar durante o boot no PS4 (evita alterar o host)
echo '/swapfile none swap defaults 0 0' >> /etc/fstab
# Apenas criamos a conf para o boot do PS4 (evita alterar o host via sysctl)
echo 'vm.swappiness=90' > /etc/sysctl.d/99-swappiness.conf

# Gerar initramfs dentro do chroot
echo "Gerando initramfs..."
mkinitcpio -k /boot/vmlinuz-linux-ps4 -g /boot/initramfs.cpio.gz || true

# Limpeza
rm -f /root/*.pkg.tar.zst
rm -f /setup.sh
CHROOTEOF

chmod +x "$ROOTFS_DIR/setup.sh"

# ── 5. Instalar kernel no chroot ──────────────────────────────────────
echo ""
echo "[5/8] Instalando kernel $KERNEL_VER no rootfs..."
mkdir -p "$ROOTFS_DIR/boot"
cp "$BZIMAGE" "$ROOTFS_DIR/boot/vmlinuz-linux-ps4"

# ── 6. Executar config chroot ─────────────────────────────────────────
echo ""
echo "[6/8] Executando configuracao e gerando initramfs (tudo via arch-chroot)..."
# O arch-chroot monta /proc, /sys, /dev automaticamente de forma segura e os desmonta na saida
arch-chroot "$ROOTFS_DIR" /setup.sh

# ── 7. Gerar initramfs ────────────────────────────────────────────────
echo ""
echo "[7/8] Initramfs ja gerado com sucesso na etapa anterior."

# ── 8. Empacotar ──────────────────────────────────────────────────────
echo ""
echo "[8/8] Compactando distro e preparando boot files..."
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*

# Rootfs tar
tar -cvJpf "$OUTPUT_DIR/$OUTPUT_TAR" -C "$ROOTFS_DIR" . --numeric-owner

# Boot files
cp "$BZIMAGE" "$OUTPUT_DIR/bzImage"
if [ -f "$ROOTFS_DIR/boot/initramfs.cpio.gz" ]; then
  cp "$ROOTFS_DIR/boot/initramfs.cpio.gz" "$OUTPUT_DIR/initramfs.cpio.gz"
fi

# Bootargs para Baikal B1 (UART 0xC890E000)
cat << 'BOOTEOF' > "$OUTPUT_DIR/bootargs.txt"
video=HDMI-A-1:1920x1080@60e panic=0 clocksource=tsc consoleblank=0 net.ifnames=0 radeon.dpm=0 amdgpu.dpm=0 drm.debug=0 console=uart8250,mmio32,0xC890E000 console=ttyS0,115200n8 console=tty0 drm.edid_firmware=edid/1920x1080.bin
BOOTEOF



echo ""
echo "=============================================="
echo " Build concluido!"
echo " Output: $OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR/"
echo "=============================================="
echo ""
echo " Para instalar no PS4:"
echo " 1. Formate pendrive: sda1 (FAT32) + sda2 (ext4)"
echo " 2. Copie para sda1: bzImage + initramfs.cpio.gz + bootargs.txt"
echo " 3. Extraia $OUTPUT_TAR para sda2"
echo " 4. Envie o payload via nc:"
echo "    nc -w 3 192.168.6.130 9090 < linux-3072mb.bin"
echo " 5. Use GoldHEN v2.4b18.9, PSFree-Enhanced:"
echo "    https://arabpixel.github.io/PSFree-Enhanced"
echo "=============================================="
