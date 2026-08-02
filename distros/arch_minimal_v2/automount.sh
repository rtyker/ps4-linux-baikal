#!/bin/bash
# ==============================================================================
# Script de Montagem Automática do HD Interno do PS4 (sda13 & sda27)
# Projeto: PS4 Linux Baikal (Kernel 7.0)
# ==============================================================================

set -e

MONTA_CMD="/usr/local/bin/monta_particao.sh"

if [ ! -x "$MONTA_CMD" ]; then
    if [ -x "$(dirname "$0")/monta_particao.sh" ]; then
        MONTA_CMD="$(dirname "$0")/monta_particao.sh"
    else
        echo "Erro: Utilitário monta_particao.sh não foi encontrado ou não tem permissão de execução!"
        exit 1
    fi
fi

echo "========================================================"
echo "⚡ Montando Partições Principais do HD Interno do PS4 ⚡"
echo "========================================================"

echo ""
echo "--> 1. Montando Partição de Sistema Orbis (/dev/sda13 - 12 GB)"
"$MONTA_CMD" /dev/sda13

echo ""
echo "--> 2. Montando Partição de Dados e Jogos (/dev/sda27 - 897.6 GB)"
"$MONTA_CMD" /dev/sda27

echo ""
echo "========================================================"
echo "✅ Montagem Automática Concluída com Sucesso!"
echo "========================================================"
echo "Mappers ativos:"
ls -lh /dev/mapper/ps4_* 2>/dev/null || true
