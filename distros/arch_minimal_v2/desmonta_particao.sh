#!/bin/bash
# ==============================================================================
# Script de Desmontagem de Partições do HD Interno do PS4 (Idempotente)
# Projeto: PS4 Linux Baikal (Kernel 7.0)
# ==============================================================================

PARTITION="$1"

if [ -z "$PARTITION" ]; then
    echo "Uso: $0 /dev/sdaX"
    echo "Exemplo: $0 /dev/sda27"
    exit 1
fi

PART_NAME=$(basename "$PARTITION")
MNT_DIR="/mnt/ps4_internal/$PART_NAME"
MAPPER_NAME="ps4_$PART_NAME"

echo "=== Desmontando $MNT_DIR ==="
if mountpoint -q "$MNT_DIR" 2>/dev/null; then
    umount "$MNT_DIR" 2>/dev/null || true
    echo "Ponto de montagem $MNT_DIR desmontado."
else
    echo "Ponto de montagem $MNT_DIR não estava montado."
fi

echo "=== Removendo mapper /dev/mapper/$MAPPER_NAME ==="
if [ -e "/dev/mapper/$MAPPER_NAME" ]; then
    cryptsetup remove "$MAPPER_NAME" 2>/dev/null || true
    echo "Mapper $MAPPER_NAME removido."
else
    echo "Mapper $MAPPER_NAME não existia."
fi

echo "Concluído: Operação de desmontagem finalizada para $PARTITION."
