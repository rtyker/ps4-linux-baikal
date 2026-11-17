#!/bin/bash
# install-spm-swap.sh <ROOTFS_DIR> - installs the systemd unit that puts swap on the Baikal SPM/DDR3.
#
# Copies baikal-spm-swap.service and, only if it is not there yet, /etc/default/baikal-spm-swap (so a
# priority the user changed is never overwritten), and enables the service. Safe to run again.
# The kernel module itself (baikal-spm-blk.ko) comes from install-modules-7.0.sh.
#
# Usage: sudo ./install-spm-swap.sh /mnt/ps4_rootfs_7.0
set -euo pipefail

ROOTFS="${1:-}"
[ -n "$ROOTFS" ] || { echo "Uso: $0 <ROOTFS_DIR>"; exit 1; }
[ -d "$ROOTFS/etc/systemd/system" ] || { echo "ERRO: $ROOTFS nao parece um rootfs systemd (sem etc/systemd/system)"; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
UNIT_SRC="$HERE/../baikal-spm-swap.service"
DEF_SRC="$HERE/../baikal-spm-swap.default"
[ -f "$UNIT_SRC" ] || { echo "ERRO: $UNIT_SRC nao encontrado"; exit 1; }
[ -f "$DEF_SRC" ]  || { echo "ERRO: $DEF_SRC nao encontrado"; exit 1; }

echo "=== install-spm-swap.sh: $ROOTFS ==="
install -Dm644 "$UNIT_SRC" "$ROOTFS/etc/systemd/system/baikal-spm-swap.service"
echo "  OK   unit instalada"

if [ -e "$ROOTFS/etc/default/baikal-spm-swap" ]; then
  echo "  --   /etc/default/baikal-spm-swap ja existe, mantido ($(grep -E '^PRIORITY=' "$ROOTFS/etc/default/baikal-spm-swap" || echo 'sem PRIORITY'))"
else
  install -Dm644 "$DEF_SRC" "$ROOTFS/etc/default/baikal-spm-swap"
  echo "  OK   /etc/default/baikal-spm-swap criado (PRIORITY=50)"
fi

mkdir -p "$ROOTFS/etc/systemd/system/multi-user.target.wants"
ln -sfn ../baikal-spm-swap.service "$ROOTFS/etc/systemd/system/multi-user.target.wants/baikal-spm-swap.service"
echo "  OK   servico habilitado em multi-user.target"

# The unit needs the module; warn if it is not in the rootfs yet.
if ls "$ROOTFS"/lib/modules/*/kernel/drivers/block/baikal-spm-blk.ko >/dev/null 2>&1; then
  echo "  OK   baikal-spm-blk.ko presente em lib/modules"
else
  echo "  AVISO: baikal-spm-blk.ko NAO esta em $ROOTFS/lib/modules; rode install-modules-7.0.sh com o build que o contem"
fi
echo "=== concluido ==="
