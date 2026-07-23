#!/bin/bash
set -e

DEVICE="/dev/sda2"
BOOTDEV="/dev/sda1"
MOUNTPOINT="/mnt/root"
LABEL="psxitarch"

if [ -z "$1" ]; then
    echo "Uso: $0 arquivo.tar.xz"
    exit 1
fi

if [ ! -b "$DEVICE" ]; then
    echo "Dispositivo $DEVICE não existe."
    exit 1
fi

# Desmonta sda1 se estiver montado
if mount | grep -q "^$BOOTDEV "; then
    echo "$BOOTDEV está montado. Desmontando..."
    sudo umount "$BOOTDEV"
fi

# Desmonta sda2 se estiver montado
if mount | grep -q "^$DEVICE "; then
    echo "$DEVICE está montado. Desmontando..."
    sudo umount "$DEVICE"
fi

echo "Formatando $DEVICE como ext4 (LABEL=$LABEL)..."
sudo mkfs.ext4 -F -L "$LABEL" "$DEVICE"

sudo mkdir -p "$MOUNTPOINT"

echo "Montando $DEVICE em $MOUNTPOINT"
sudo mount "$DEVICE" "$MOUNTPOINT"

echo "Extraindo $1 em $MOUNTPOINT"
sudo tar -xvJpf "$1" -C "$MOUNTPOINT" --numeric-owner

echo "Sincronizando disco..."
sync

echo "Desmontando $DEVICE"
sudo umount "$MOUNTPOINT"

echo "Concluído."
