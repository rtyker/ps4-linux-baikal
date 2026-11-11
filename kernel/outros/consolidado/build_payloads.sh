#!/bin/bash
# Script de compilacao dos payloads PS4 Linux (Totalmente isolado do build da distro)
set -e

PAYLOADS_SRC_DIR="../ps4-linux-payloads/linux"
OUTPUT_DIR="./payload_output"

echo "=============================================="
echo " Compilador de Payloads PS4 Linux"
echo "=============================================="

if [ ! -d "$PAYLOADS_SRC_DIR" ]; then
  echo "ERRO: Diretorio de codigo-fonte do payload nao encontrado em $PAYLOADS_SRC_DIR"
  exit 1
fi

# Verifica se ferramentas basicas estao instaladas
if ! command -v make &> /dev/null; then
  echo "ERRO: 'make' nao esta instalado no host."
  exit 1
fi

if ! command -v gcc &> /dev/null; then
  echo "ERRO: 'gcc' nao esta instalado no host."
  exit 1
fi

# Acessa a pasta e compila os payloads
echo "Limpando builds anteriores..."
make -C "$PAYLOADS_SRC_DIR" clean

echo "Iniciando compilacao..."
make -C "$PAYLOADS_SRC_DIR" -j$(nproc)

# Prepara pasta de saida
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*

# Copia os payloads gerados (.bin e .elf)
echo "Copiando payloads gerados para $OUTPUT_DIR..."
cp "$PAYLOADS_SRC_DIR"/payloads/linux-*.bin "$OUTPUT_DIR/" 2>/dev/null || true
cp "$PAYLOADS_SRC_DIR"/payloads/linux-*.elf "$OUTPUT_DIR/" 2>/dev/null || true

echo "=============================================="
echo " Build de Payloads concluido!"
echo " Outputs salvos em: $OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR/"
echo "=============================================="
