#!/bin/bash
# ssh-startup.sh — Inicializa SSH automaticamente no final do boot
# Cria todas as estruturas necessárias para SSH funcionar

set -e

ROOTFS_MNT="/mnt/ps4-rootfs"
ROOTFS_DEV="/dev/sdb2"

# Espera o rootfs estar disponível
for attempt in {1..30}; do
  if [ -b "$ROOTFS_DEV" ]; then
    break
  fi
  sleep 0.5
done

if [ ! -b "$ROOTFS_DEV" ]; then
  echo "Erro: $ROOTFS_DEV não disponível" >&2
  exit 1
fi

# Monta rootfs se ainda não montado
if ! mountpoint -q "$ROOTFS_MNT"; then
  mkdir -p "$ROOTFS_MNT"
  mount -o ro "$ROOTFS_DEV" "$ROOTFS_MNT" 2>/dev/null || exit 1
fi

# Prepara pseudo-filesystems para chroot
for fs in proc sys dev run; do
  if ! mountpoint -q "$ROOTFS_MNT/$fs" 2>/dev/null; then
    case "$fs" in
      proc) mount -t proc proc "$ROOTFS_MNT/proc" 2>/dev/null || true ;;
      sys) mount --rbind /sys "$ROOTFS_MNT/sys" 2>/dev/null || true ;;
      dev) mount --rbind /dev "$ROOTFS_MNT/dev" 2>/dev/null || true ;;
      run) mount --rbind /run "$ROOTFS_MNT/run" 2>/dev/null || true ;;
    esac
  fi
done

# Inicia sshd dentro do chroot
chroot "$ROOTFS_MNT" /usr/sbin/sshd -D &

echo "SSH iniciado no chroot em $ROOTFS_MNT"
