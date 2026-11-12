#!/bin/bash
# rebuild-initramfs-7.0.sh [TAG] — Reconstrói o initramfs do kernel 7.0 depois
# de mexer nos hooks do rootfs já instalado (ex: mudança no mkinitcpio.conf).
#
# A versão do kernel é detectada DENTRO do rootfs montado (não no host) e o
# initramfs é gravado POR TAG em boot_referencia/, com o mesmo nome que
# deploy-boot-7.0.sh e promote-release.sh esperam.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOT_DIR="${PS4_BOOT_REF:-$SCRIPT_DIR/boot_referencia}"
ROOTFS_MNT="${PS4_ROOTFS_MNT:-/mnt/ps4_rootfs_7.0}"
TAG="${1:-${TAG:-}}"

[ "$EUID" -eq 0 ] || { echo "Execute com sudo"; exit 1; }

# REGRA CRÍTICA (AGENTS.md): NUNCA montar direto em /mnt — usar subdir dedicado.
if [ "$ROOTFS_MNT" = "/mnt" ]; then
  echo "ERRO: \$ROOTFS_MNT não pode ser /mnt — use um subdir dedicado (ex: /mnt/ps4_rootfs_7.0)"; exit 1
fi

# Montar rootfs se não estiver montado
if ! mountpoint -q "$ROOTFS_MNT"; then
  echo "Montando rootfs em $ROOTFS_MNT..."
  mkdir -p "$ROOTFS_MNT"
  # Preferência: pelo LABEL (o mesmo que o initramfs monta), depois devices comuns
  mount LABEL=psxitarch "$ROOTFS_MNT" 2>/dev/null \
    || mount /dev/sda2 "$ROOTFS_MNT" 2>/dev/null \
    || mount /dev/nvme0n1p2 "$ROOTFS_MNT" 2>/dev/null \
    || {
      echo "Erro: não foi possível montar o rootfs (LABEL=psxitarch, /dev/sda2, /dev/nvme0n1p2)."
      echo "      Monte manualmente em $ROOTFS_MNT e rode de novo."
      exit 1
    }
fi

# Versão do kernel: DENTRO do rootfs (o host pode ter outro kernel instalado)
KVER_FULL=""
for _d in "$ROOTFS_MNT"/lib/modules/7.*; do
  [ -d "$_d" ] || continue
  KVER_FULL="$(basename "$_d")"
  break
done
if [ -z "$KVER_FULL" ]; then
  echo "Erro: nenhum kernel 7.x encontrado em $ROOTFS_MNT/lib/modules/"
  exit 1
fi
echo "Kernel version: $KVER_FULL"

if [ -z "$TAG" ]; then
  mapfile -t _TAGS < <(cd "$BOOT_DIR" 2>/dev/null && ls -1 bzImage-7.0-* 2>/dev/null | sed 's/^bzImage-7\.0-//')
  case "${#_TAGS[@]}" in
    0) echo "ERRO: nenhuma tag em $BOOT_DIR e nenhum TAG informado."; exit 1 ;;
    1) TAG="${_TAGS[0]}"; echo "=== TAG autodetectada: $TAG ===" ;;
    *) echo "ERRO: multiplas tags em $BOOT_DIR — informe: $0 <TAG>"; exit 1 ;;
  esac
fi

# Copiar EDID
mkdir -p "$ROOTFS_MNT/lib/firmware/edid"
cp "$SCRIPT_DIR/ps4_tv_edid.bin" "$ROOTFS_MNT/lib/firmware/edid/ps4_tv_edid.bin"

# Rebuild initramfs
arch-chroot "$ROOTFS_MNT" mkinitcpio -k "$KVER_FULL" -g "/boot/initramfs-$KVER_FULL.img"

# Copiar para boot_referencia, POR TAG
OUT="$BOOT_DIR/initramfs-7.0-$TAG.cpio.gz"
cp "$ROOTFS_MNT/boot/initramfs-$KVER_FULL.img" "$OUT"

echo "=== Initramfs 7.0 reconstruído ==="
echo "Arquivo: $OUT"
echo "Para ativar no HD (boot-only, mantém o rootfs):"
echo "  sudo ./deploy-boot-7.0.sh $TAG"
