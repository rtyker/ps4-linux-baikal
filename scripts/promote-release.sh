#!/bin/bash
# promote-release.sh <TAG> [--no-tar]
# Monta RELEASE/<TAG>/ com os artefatos compilados da tag:
#   bzImage, config, bootargs, initramfs  (copiados de boot_referencia/)
#   arch_minimal_v2-7.0.tar               (symlink para o tarball da distro,
#                                          que é gravado por 01-build-image-7.0.sh
#                                          em distros/arch_minimal_v2/ e pesa ~16GB)
#
# Isso mantém o pipeline oficial intacto (scripts continuam gravando em
# boot_referencia/) e faz do RELEASE/ apenas a vitrine final de cada tag.
# Gera sha256sums.txt com a soma dos arquivos copiados.
#
# Requer que a tag exista completa em boot_referencia/ (4 arquivos), igual ao
# deploy-boot-7.0.sh — sem fallback silencioso para o initramfs genérico.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOT_REF="$PROJECT_ROOT/distros/arch_minimal_v2/boot_referencia"
TAR_SRC="$PROJECT_ROOT/distros/arch_minimal_v2/arch_minimal_v2-7.0.tar"

TAG="${1:?Uso: $0 <TAG> [--no-tar]}"
NO_TAR="${2:-}"
RELEASE_DIR="$PROJECT_ROOT/RELEASE/$TAG"

BZIMAGE="$BOOT_REF/bzImage-7.0-$TAG"
CONFIG="$BOOT_REF/config-7.0-$TAG"
BOOTARGS="$BOOT_REF/bootargs-7.0-$TAG.txt"
INITRAMFS="$BOOT_REF/initramfs-7.0-$TAG.cpio.gz"

echo "=== Promovendo tag: $TAG ==="

[ -f "$BZIMAGE" ]  || { echo "ERRO: $BZIMAGE não encontrado"; exit 1; }
[ -f "$CONFIG" ]   || { echo "ERRO: $CONFIG não encontrado"; exit 1; }
[ -f "$BOOTARGS" ] || { echo "ERRO: $BOOTARGS não encontrado"; exit 1; }
[ -f "$INITRAMFS" ] || {
  echo "ERRO: $INITRAMFS não encontrado."
  echo "Cada tag precisa do seu próprio initramfs. Para reusar o de outra tag:"
  echo "  cp $BOOT_REF/initramfs-7.0-<tag_origem>.cpio.gz $INITRAMFS"
  exit 1
}
if [ "$NO_TAR" != "--no-tar" ]; then
  [ -f "$TAR_SRC" ] || { echo "ERRO: tarball da distro $TAR_SRC não encontrado"; exit 1; }
fi

mkdir -p "$RELEASE_DIR"

cp -f "$BZIMAGE"  "$RELEASE_DIR/"
cp -f "$CONFIG"   "$RELEASE_DIR/"
cp -f "$BOOTARGS" "$RELEASE_DIR/"
cp -f "$INITRAMFS" "$RELEASE_DIR/"

if [ "$NO_TAR" != "--no-tar" ]; then
  TAR_DST="$RELEASE_DIR/arch_minimal_v2-7.0-$TAG.tar"
  if [ -e "$TAR_DST" ] && [ ! -L "$TAR_DST" ]; then
    echo "AVISO: $TAR_DST já existe como arquivo real; mantido."
  else
    ln -sf "$TAR_SRC" "$TAR_DST"
  fi
fi

(
  cd "$RELEASE_DIR"
  sha256sum bzImage-7.0-$TAG config-7.0-$TAG bootargs-7.0-$TAG.txt \
            initramfs-7.0-$TAG.cpio.gz \
  > sha256sums.txt
  if [ "$NO_TAR" != "--no-tar" ] && [ -L "arch_minimal_v2-7.0-$TAG.tar" ]; then
    sha256sum "$TAR_SRC" >> sha256sums.txt
  fi
)

echo
echo "=== RELEASE/$TAG pronto ==="
ls -la "$RELEASE_DIR"
