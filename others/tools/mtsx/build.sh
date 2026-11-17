#!/bin/bash
# Build mtsx.ko out of tree against kernel/kernel_build_7.0.
#
# Same mechanism and toolchain flags as others/scripts/build_mts_module.sh (the
# validated one for mts.ko); the only difference is that the module lives outside
# the kernel tree, so nothing is copied into it. Needs sudo because the kernel
# tree is root-owned; the outputs are handed back to the invoking user.
#
# The module only loads on the kernel that matches the tree. Check before use:
#   modinfo mtsx.ko | grep vermagic      # on this host
#   uname -r                                 # on the console (after the user boots it)
# Tree and tag are the same build when Module.symvers and the bzImage of the tag
# have the same timestamp (see others/docs/PLAN_ETH0_BAIKAL.md, Phase A).
#
# Usage: sudo ./build.sh            (W=1 sudo -E ./build.sh for extra warnings)

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KERNEL_BUILD_DIR="$HERE/../../../kernel/kernel_build_7.0"

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: run with sudo (the kernel tree is root-owned)." >&2
    exit 1
fi
if [ ! -f "$KERNEL_BUILD_DIR/Module.symvers" ]; then
    echo "ERROR: $KERNEL_BUILD_DIR has no Module.symvers; build the kernel with the official script first." >&2
    exit 1
fi

make -C "$KERNEL_BUILD_DIR" \
     M="$HERE" \
     ARCH=x86_64 \
     CC=clang \
     LD=ld.lld \
     AR=llvm-ar \
     NM=llvm-nm \
     ${W:+W=$W} \
     -j"$(nproc)" \
     modules

if [ -n "${SUDO_USER:-}" ]; then
    chown -R "$SUDO_USER":"$(id -gn "$SUDO_USER")" "$HERE"
fi

echo
echo "Built: $HERE/mtsx.ko"
modinfo "$HERE/mtsx.ko" | grep -E '^(filename|description|vermagic|parm)'
echo "Tree timestamps (compare with the deployed tag's bzImage):"
ls -l --time-style=+%F_%T "$KERNEL_BUILD_DIR/Module.symvers" | awk '{print "  " $6 "  " $7}'
