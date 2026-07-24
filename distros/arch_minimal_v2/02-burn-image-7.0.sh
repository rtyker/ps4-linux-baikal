#!/bin/bash
# Grava Arch Minimal v2 kernel 7.0 no HD para PS4
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOT_REF="$SCRIPT_DIR/boot_referencia"
DEV="${1:-/dev/sda}"
ROOTFS_TAR="${2:-$SCRIPT_DIR/arch_minimal_v2-7.0.tar}"

[ "$EUID" -eq 0 ] || { echo "Execute com sudo"; exit 1; }
[ -b "$DEV" ] || { echo "$DEV nao encontrado"; exit 1; }
[ -f "$ROOTFS_TAR" ] || { echo "Rootfs $ROOTFS_TAR nao encontrado"; exit 1; }
[ -f "$BOOT_REF/bzImage-7.0" ] || { echo "Kernel 7.0 nao encontrado"; exit 1; }
[ -f "$BOOT_REF/initramfs-7.0.cpio.gz" ] || { echo "Initramfs 7.0 nao encontrado"; exit 1; }
[ -f "$BOOT_REF/bootargs-7.0.txt" ] || { echo "Bootargs 7.0 nao encontrado"; exit 1; }

BOOT="${DEV}1"
ROOT="${DEV}2"

echo "=== Desmontando partições antigas ==="
umount -l "$BOOT" 2>/dev/null || true
umount -l "$ROOT" 2>/dev/null || true
umount -l /mnt/boot 2>/dev/null || true
umount -l /mnt/root 2>/dev/null || true

echo "=== Particionando $DEV (kernel 7.0) ==="
fdisk "$DEV" <<EOF
o
n
p
1

+200M
t
b
a
1
n
p
2


w
EOF

partprobe "$DEV" || sleep 1
udevadm settle 2>/dev/null || true

# udisks2 remonta automaticamente as partições assim que a nova tabela
# aparece (antes do mkfs rodar) - desmontar de novo defensivamente
sleep 1
umount -l "$BOOT" 2>/dev/null || true
umount -l "$ROOT" 2>/dev/null || true

echo "=== Formatando ==="
mkfs.vfat -F 32 "$BOOT" -n BOOT
umount -l "$ROOT" 2>/dev/null || true
mkfs.ext4 -q -F -L psxitarch "$ROOT"

echo "=== Montando ==="
mkdir -p /mnt/boot /mnt/root
mount "$BOOT" /mnt/boot
mount "$ROOT" /mnt/root

echo "=== Copiando boot (kernel 7.0) ==="
cp "$BOOT_REF/bzImage-7.0"          /mnt/boot/bzImage
cp "$BOOT_REF/initramfs-7.0.cpio.gz" /mnt/boot/initramfs.cpio.gz
cp "$BOOT_REF/bootargs-7.0.txt"      /mnt/boot/bootargs.txt
cp "$BOOT_REF/vram.txt"              /mnt/boot/vram.txt
touch /mnt/boot/bootlog.txt

echo "=== Extraindo rootfs (numeric-owner) ==="
tar -xpf "$ROOTFS_TAR" -C /mnt/root --numeric-owner
sync

echo "=== Desmontando ==="
umount /mnt/root /mnt/boot

echo "=== Concluido (kernel 7.0) ==="
echo "Desconecte o HD, conecte no PS4, envie payload via Payload Guest"
echo "Login: ps4 / ps4"