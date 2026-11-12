#!/bin/bash
# ==============================================================================
# Helper script: Montagem de Partições do HD Interno do PS4 com Tweak LBA Corrigido
# ==============================================================================
# Baseado nos achados da Engenharia Reversa do GEOM_CRYPT (0xffffffffdc9a40d0):
# 1. Chave ERK (32 bytes = 256 bits) do EAP em /etc/ps4_keys.bin
# 2. Tweak IV/sector offset = LBA absoluto em disco (setores de 512B) via --skip
# ==============================================================================

set -euo pipefail

PARTITION="${1:-}"

if [ -z "$PARTITION" ]; then
    echo "Uso: $0 /dev/sdaX [opcional: /media/ponto_montagem]"
    echo "Exemplo: $0 /dev/sda13"
    echo "Exemplo: $0 /dev/sda27"
    exit 1
fi

MNT_TARGET="${2:-}"
PART_NAME=$(basename "$PARTITION")
MAPPER_NAME="ps4_$PART_NAME"
KEY_FILE="/etc/ps4_keys.bin"

if [ ! -f "$KEY_FILE" ]; then
    if [ -f "/tmp/keys.bin" ]; then
        KEY_FILE="/tmp/keys.bin"
    else
        echo "Erro: Arquivo de chave $KEY_FILE não encontrado."
        exit 1
    fi
fi

# Obter LBA inicial da partição em setores de 512B via lsblk ou sfdisk
DISK_DEVICE="/dev/$(lsblk -no pkname "$PARTITION" 2>/dev/null || echo sda)"
START_SECTOR=$(lsblk -bno START "$PARTITION" 2>/dev/null || echo "")

if [ -z "$START_SECTOR" ]; then
    # Fallback: tentar sgdisk/sfdisk
    START_SECTOR=$(sfdisk -l "$DISK_DEVICE" 2>/dev/null | grep "$PARTITION" | awk '{print $2}' || echo "0")
fi

echo "=== Informações da Partição ==="
echo "  Dispositivo:    $PARTITION"
echo "  Disco base:     $DISK_DEVICE"
echo "  Setor LBA:      $START_SECTOR (512B)"
echo "  Mapper:         /dev/mapper/$MAPPER_NAME"
echo "  Chave:          $KEY_FILE (256 bits)"

# Criar mapper cryptsetup com --skip igual ao LBA inicial absoluto
SIZE_SECTORS=$(lsblk -bno SECTORS "$PARTITION" 2>/dev/null || echo "")

if [ -e "/dev/mapper/$MAPPER_NAME" ]; then
    echo "Mapper /dev/mapper/$MAPPER_NAME já existe, mantendo estado..."
else
    echo "Abrindo mapper no disco $DISK_DEVICE com offset LBA absoluto (--offset $START_SECTOR --size $SIZE_SECTORS)..."
    cryptsetup open --type plain "$DISK_DEVICE" "$MAPPER_NAME" \
        --cipher aes-xts-plain64 \
        --key-file "$KEY_FILE" \
        --key-size 256 \
        --offset "$START_SECTOR" \
        ${SIZE_SECTORS:+--size $SIZE_SECTORS} \
        --readonly
fi

echo "Mapper /dev/mapper/$MAPPER_NAME pronto."

if [ -n "$MNT_TARGET" ]; then
    mkdir -p "$MNT_TARGET"
    echo "Montando em $MNT_TARGET..."
    if ps4_pfs_fuse "/dev/mapper/$MAPPER_NAME" "$MNT_TARGET" 2>/dev/null; then
        echo "Montado via ps4_pfs_fuse em $MNT_TARGET"
    else
        mount -o ro "/dev/mapper/$MAPPER_NAME" "$MNT_TARGET" || true
    fi
fi
