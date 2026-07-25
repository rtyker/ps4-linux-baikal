#!/bin/bash
# rebuild-initramfs-7.0.sh — Reconstrói initramfs do kernel 7.0 após mudanças de hooks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOT_DIR="$SCRIPT_DIR/boot_referencia"
ROOTFS_MNT="/mnt/ps4_rootfs_7.0"

# Detectar versão do kernel 7.0 instalada
KVER_FULL=$(ls /usr/lib/modules/ | grep -E '^7\.' | head -1)
if [ -z "$KVER_FULL" ]; then
  echo "Erro: Nenhum kernel 7.x encontrado em /usr/lib/modules/"
  exit 1
fi

echo "Kernel version: $KVER_FULL"

# Montar rootfs se não estiver montado
if ! mountpoint -q "$ROOTFS_MNT"; then
  echo "Montando rootfs em $ROOTFS_MNT..."
  mkdir -p "$ROOTFS_MNT"
  # Ajuste conforme seu device
  mount /dev/sda2 "$ROOTFS_MNT" 2>/dev/null || mount /dev/nvme0n1p2 "$ROOTFS_MNT" 2>/dev/null || {
    echo "Erro: Não foi possível montar rootfs. Monte manualmente em $ROOTFS_MNT"
    exit 1
  }
fi

# Copiar EDID
mkdir -p "$ROOTFS_MNT/lib/firmware/edid"
cp "$SCRIPT_DIR/ps4_tv_edid.bin" "$ROOTFS_MNT/lib/firmware/edid/ps4_tv_edid.bin"

# Rebuild initramfs
arch-chroot "$ROOTFS_MNT" mkinitcpio -k "$KVER_FULL" -g "/boot/initramfs-$KVER_FULL.img"

# Copiar para boot_referencia
cp "$ROOTFS_MNT/boot/initramfs-$KVER_FULL.img" "$BOOT_DIR/initramfs-7.0.cpio.gz"

echo "=== Initramfs 7.0 reconstruído ==="
echo "Arquivo: $BOOT_DIR/initramfs-7.0.cpio.gz"
echo "Para gravar na partição de boot:"
echo "  sudo cp $BOOT_DIR/initramfs-7.0.cpio.gz /mnt/boot/"