#!/bin/bash
# Build mtsx.ko out of tree against kernel/kernel_build_7.0.
#
# A FONTE do driver é única e vive em kernel/drivers_mts/ (mtsx.c +
# mtsx_desc.h) — a mesma que o build oficial compila como mtsx.ko dentro da
# árvore. Este script existe só para o ciclo rápido de compilação/teste fora da
# árvore: ele copia a fonte canônica para um diretório temporário, compila com
# as mesmas flags de others/scripts/build_mts_module.sh e devolve o .ko aqui.
# Nada é copiado para dentro da árvore do kernel.
#
# O módulo só carrega no kernel que casa com a árvore. Confira antes de usar:
#   modinfo mtsx.ko | grep vermagic      # neste host
#   uname -r                                 # no console
# Árvore e tag são o mesmo build quando Module.symvers e o bzImage da tag têm o
# mesmo timestamp (ver others/docs/PLAN_ETH0_BAIKAL.md, Fase A).
#
# Usage: sudo ./build.sh            (W=1 sudo -E ./build.sh for extra warnings)

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KERNEL_BUILD_DIR="$HERE/../../../kernel/kernel_build_7.0"
SRC_DIR="$HERE/../../../kernel/drivers_mts"

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: run with sudo (the kernel tree is root-owned)." >&2
    exit 1
fi
if [ ! -f "$KERNEL_BUILD_DIR/Module.symvers" ]; then
    echo "ERROR: $KERNEL_BUILD_DIR has no Module.symvers; build the kernel with the official script first." >&2
    exit 1
fi
for f in mtsx.c mtsx_desc.h; do
    [ -f "$SRC_DIR/$f" ] || { echo "ERROR: fonte canônica ausente: $SRC_DIR/$f" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp "$SRC_DIR/mtsx.c" "$SRC_DIR/mtsx_desc.h" "$WORK/"
echo "obj-m += mtsx.o" > "$WORK/Kbuild"

make -C "$KERNEL_BUILD_DIR" \
     M="$WORK" \
     ARCH=x86_64 \
     CC=clang \
     LD=ld.lld \
     AR=llvm-ar \
     NM=llvm-nm \
     ${W:+W=$W} \
     -j"$(nproc)" \
     modules

cp "$WORK/mtsx.ko" "$HERE/mtsx.ko"

if [ -n "${SUDO_USER:-}" ]; then
    chown -R "$SUDO_USER":"$(id -gn "$SUDO_USER")" "$HERE"
fi

echo
echo "Built: $HERE/mtsx.ko"
modinfo "$HERE/mtsx.ko" | grep -E '^(filename|description|vermagic|parm)'
echo "Tree timestamps (compare with the deployed tag's bzImage):"
ls -l --time-style=+%F_%T "$KERNEL_BUILD_DIR/Module.symvers" | awk '{print "  " $6 "  " $7}'
