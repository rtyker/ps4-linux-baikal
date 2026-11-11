#!/bin/bash
# ==============================================================================
# Script de Montagem de Partições do HD Interno do PS4 (Read-Only & Idempotente)
# Projeto: PS4 Linux Baikal (Kernel 7.0)
# ==============================================================================

set -e

PARTITION="$1"

if [ -z "$PARTITION" ]; then
    echo "Uso: $0 /dev/sdaX"
    echo "Exemplo: $0 /dev/sda27"
    exit 1
fi

PART_NAME=$(basename "$PARTITION")
MNT_DIR="/mnt/ps4_internal/$PART_NAME"
MAPPER_NAME="ps4_$PART_NAME"
KEY_FILE="/etc/ps4_keys.bin"

if [ ! -f "$KEY_FILE" ]; then
    if [ -f "/tmp/keys.bin" ]; then
        KEY_FILE="/tmp/keys.bin"
    else
        echo "Erro: Arquivo de chave do PS4 ($KEY_FILE ou /tmp/keys.bin) não encontrado!"
        exit 1
    fi
fi

if [ ! -b "$PARTITION" ]; then
    echo "Erro: Dispositivo $PARTITION não encontrado!"
    exit 1
fi

mkdir -p "$MNT_DIR"

# 1. Checagem idempotente de montagem existente
if mountpoint -q "$MNT_DIR" 2>/dev/null; then
    echo "Info: $MNT_DIR já está montado."
    exit 0
fi

# 2. Checagem idempotente do mapper cryptsetup
echo "=== Mapeando partição $PARTITION com cryptsetup (Read-Only) ==="
if [ -e "/dev/mapper/$MAPPER_NAME" ]; then
    echo "Mapper /dev/mapper/$MAPPER_NAME já existe, reutilizando..."
else
    cryptsetup create "$MAPPER_NAME" "$PARTITION" \
        --cipher aes-xts-plain64 \
        --key-file "$KEY_FILE" \
        --key-size 256 \
        --readonly
fi

# 3. Tentativa de montagem somente-leitura
echo "=== Montando /dev/mapper/$MAPPER_NAME em $MNT_DIR (Read-Only) ==="
if mount -t ufs -o ufstype=ufs2,ro "/dev/mapper/$MAPPER_NAME" "$MNT_DIR" 2>/dev/null; then
    echo "Sucesso: Montado como UFS2 em $MNT_DIR"
elif mount -o ro "/dev/mapper/$MAPPER_NAME" "$MNT_DIR" 2>/dev/null; then
    echo "Sucesso: Montado em $MNT_DIR"
else
    echo "Aviso: Mapeamento /dev/mapper/$MAPPER_NAME ativo em modo Read-Only."
    echo "Dispositivo de bloco descriptografado disponível em /dev/mapper/$MAPPER_NAME."
fi
