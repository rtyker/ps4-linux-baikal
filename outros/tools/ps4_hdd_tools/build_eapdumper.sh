#!/usr/bin/env bash
#
# build_eapdumper.sh — compila o payload EAPDumper (projeto de terceiros:
# https://github.com/seregonwar/EAPDumper) para extrair a chave EAP do HD do PS4.
#
# O payload roda no Orbis (via GoldHEN), NÃO no Linux. Ele lê a chave da memória
# do kernel Sony (ou de /system_data/priv/eap/eap_hdd_key.bin) e grava em:
#   /data/hddeap/eap_hdd_key.bin   (obrigatório, no PS4)
#   /mnt/usb0/eap_hdd_key.bin      (best-effort, se houver USB)
#
# Pré-requisitos:
#   - llvm/clang/lld (>= 18) no host  -> testado com LLVM 19.1.7 (Debian)
#   - ps4-payload-sdk (John Törnblom) -> release v0.9, extraído em
#     outros/tools/ps4_hdd_tools/EAPDumper/ps4-payload-sdk
#
# Uso:
#   ./build_eapdumper.sh              # compila (EAPDumper + EAP-Scanner)
#   ./build_eapdumper.sh --check      # só valida pré-requisitos
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/EAPDumper"
SDK_DIR="$SRC_DIR/ps4-payload-sdk"
LLVM_CONFIG="${LLVM_CONFIG:-$(command -v llvm-config || true)}"

die() { echo "ERRO: $*" >&2; exit 1; }

# --- checagens ---------------------------------------------------------------
[ -d "$SRC_DIR" ] || die "fonte não encontrada em $SRC_DIR (clone https://github.com/seregonwar/EAPDumper.git)"

if [ -z "$LLVM_CONFIG" ]; then
    die "llvm-config não encontrado (instale llvm/clang/lld ou defina LLVM_CONFIG=...)"
fi

if [ ! -f "$SDK_DIR/toolchain/orbis.mk" ]; then
    cat >&2 <<EOF
ERRO: ps4-payload-sdk ausente em $SDK_DIR

Baixe a release oficial e extraia dentro de $SRC_DIR:

  cd "$SRC_DIR"
  curl -sSLo sdk.zip https://github.com/ps4-payload-dev/sdk/releases/latest/download/ps4-payload-sdk.zip
  unzip -q sdk.zip          # cria ./ps4-payload-sdk

Atenção: copie SEMPRE com 'cp -a' ou 'unzip' — 'cp -r' dereferencia os
symlinks de bin/ (orbis-llvm, orbis-ld, ...) e o link quebra com
"cannot find linker script /ldscripts/elf_x86_64.x".
EOF
    exit 1
fi

echo "LLVM_CONFIG = $LLVM_CONFIG ($("$LLVM_CONFIG" --version))"
echo "SDK         = $SDK_DIR"
echo

[ "${1:-}" = "--check" ] && { echo "Pré-requisitos OK."; exit 0; }

# --- build -------------------------------------------------------------------
# A variável PS4_PAYLOAD_SDK PRECISA estar no ambiente: o wrapper orbis-ld a usa
# para localizar ldscripts/elf_x86_64.x (o Makefile do projeto não a exporta).
cd "$SRC_DIR"
make clean >/dev/null 2>&1 || true
PS4_PAYLOAD_SDK="$SDK_DIR" LLVM_CONFIG="$LLVM_CONFIG" make

echo
echo "=== Artefatos ==="
ls -l "$SRC_DIR/EAPDumper.bin" "$SRC_DIR/EAP-Scanner.bin"
sha256sum "$SRC_DIR/EAPDumper.bin" "$SRC_DIR/EAP-Scanner.bin"
