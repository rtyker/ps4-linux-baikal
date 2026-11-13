#!/bin/bash
# ==============================================================================
# Desmontagem de uma partição do HD interno do PS4 (Idempotente)
# Projeto: PS4 Linux Baikal (Kernel 7.0)
#
# Remove o mount em /mnt/ps4_internal/<part> e o mapper dm-crypt ps4_<part>.
# O mapper agora é criado com `dmsetup` (iv_offset != 0), então usamos
# `dmsetup remove` com fallback para `cryptsetup remove` (compatibilidade com
# mappers antigos, criados pelo esquema de IV relativo).
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
    umount "$MNT_DIR" 2>/dev/null && echo "Desmontado: $MNT_DIR" \
        || echo "Aviso: falha ao desmontar $MNT_DIR (processo usando o diretório?)"
else
    echo "Ponto de montagem $MNT_DIR não estava montado."
fi

echo "=== Removendo mapper /dev/mapper/$MAPPER_NAME ==="
if [ -e "/dev/mapper/$MAPPER_NAME" ]; then
    if dmsetup remove "$MAPPER_NAME" 2>/dev/null || cryptsetup remove "$MAPPER_NAME" 2>/dev/null; then
        echo "Mapper $MAPPER_NAME removido."
    else
        echo "Aviso: falha ao remover $MAPPER_NAME (ainda em uso?)."
    fi
else
    echo "Mapper $MAPPER_NAME não existia."
fi

echo "Concluído: desmontagem finalizada para $PARTITION."
