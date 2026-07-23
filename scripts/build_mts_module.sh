#!/bin/bash
# scripts/build_mts_module.sh — Compila o módulo mts.ko usando a árvore do kernel e o toolchain idêntico (GCC)


set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
KERNEL_BUILD_DIR="/mnt/hdauxiliar/temp/kernel_build_7.0"
MTS_SRC_DIR="$PROJECT_ROOT/drivers_mts"
MTS_BUILD_DIR="$MTS_SRC_DIR/build"

echo "=== Compilação Isolada do Módulo mts.ko ==="

# 1. Verificar se está rodando como root (necessário devido às permissões da árvore do kernel)
if [ "$EUID" -ne 0 ]; then
    echo "[-] ERRO: Este script precisa ser executado com sudo."
    exit 1
fi

# 2. Verificar se a árvore do kernel existe
if [ ! -d "$KERNEL_BUILD_DIR" ]; then
    echo "[-] ERRO: Diretório de build do kernel não encontrado em $KERNEL_BUILD_DIR"
    exit 1
fi

# 3. Sincronizar fontes do driver para a árvore do kernel
echo "[+] Copiando fontes atualizados de $MTS_SRC_DIR para a árvore do kernel..."
mkdir -p "$KERNEL_BUILD_DIR/drivers/net/ethernet/sony"
cp -v "$MTS_SRC_DIR/mts.c" "$KERNEL_BUILD_DIR/drivers/net/ethernet/sony/mts.c"
cp -v "$MTS_SRC_DIR/mts.h" "$KERNEL_BUILD_DIR/drivers/net/ethernet/sony/mts.h"

# 4. Compilar o módulo usando os mesmos parâmetros do Kernel (GCC / ARCH=x86_64)
echo "[+] Compilando módulo mts.ko com GCC..."
make -C "$KERNEL_BUILD_DIR" \
     M="drivers/net/ethernet/sony" \
     ARCH=x86_64 \
     -j"$(nproc)" \
     modules

# 5. Copiar o binário gerado de volta para a pasta build do projeto
COMPILED_KO="$KERNEL_BUILD_DIR/drivers/net/ethernet/sony/mts.ko"

if [ -f "$COMPILED_KO" ]; then
    echo "[+] Módulo compilado com sucesso!"
    mkdir -p "$MTS_BUILD_DIR"
    cp -v "$COMPILED_KO" "$MTS_BUILD_DIR/mts.ko"
    echo "    - Módulo copiado para: $MTS_BUILD_DIR/mts.ko"
    
    # 6. Remover seções BTF para evitar erros de validação distilada no kernel ("failed to validate module BTF")
    echo "[+] Removendo seções .BTF e .BTF.base para evitar rejeição no insmod..."
    objcopy --remove-section=.BTF --remove-section=.BTF.base "$MTS_BUILD_DIR/mts.ko"
    echo "    - BTF removido de: $MTS_BUILD_DIR/mts.ko"
else
    echo "[-] ERRO: mts.ko não encontrado após a compilação."
    exit 1
fi
