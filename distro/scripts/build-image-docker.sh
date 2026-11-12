#!/bin/bash
# build-image-docker.sh <TAG> — roda o build OFICIAL da distro (01-build-image-7.0.sh)
# dentro de um container Arch Linux oficial.
#
# POR QUE ISTO EXISTE
# O build da distro depende de um host Arch: pacstrap/pacman/arch-chroot são
# ferramentas Arch (não existem em Debian/Ubuntu). Em vez de poluir o host com
# pacman "foreign", o build roda num container oficial archlinux:latest, com o
# repositório e a área de build montados por bind-mount — os arquivos saem
# direto no disco do host, com owner root, exatamente como no host Arch.
#
# O script NÃO substitui o 01-build-image-7.0.sh: ele apenas o executa dentro
# do container. Toda a lógica (pacstrap, pacotes, mkinitcpio, bootargs, tar do
# rootfs) continua sendo a do script oficial.
#
# Uso:
#   sudo ./scripts/build-image-docker.sh <TAG>
#
# Env:
#   PS4_BUILD_IMAGE   imagem base (default: archlinux:latest)
#   PS4_BUILD_ROOT    area de build (default: /mnt/hdauxiliar/temp/arch_build_7.0)
#   PS4_BUILD_CACHE   cache do pacman compartilhado (default: /mnt/hdauxiliar/temp/pacman-cache)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISTRO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$DISTRO_DIR/.." && pwd)"

TAG="${1:?Uso: $0 <TAG>}"
IMAGE="${PS4_BUILD_IMAGE:-archlinux:latest}"
BUILD_ROOT="${PS4_BUILD_ROOT:-/mnt/hdauxiliar/temp/arch_build_7.0}"
CACHE_DIR="${PS4_BUILD_CACHE:-/mnt/hdauxiliar/temp/pacman-cache}"

# O build precisa de disco ext4: /mnt/t é NTFS e quebra mount/chroot.
case "$BUILD_ROOT" in
  /mnt/t|/mnt/t/*)
    echo "ERRO: BUILD_ROOT em NTFS ($BUILD_ROOT) — use disco ext4 (ex: /mnt/hdauxiliar)."
    exit 1 ;;
esac

command -v docker >/dev/null || { echo "ERRO: docker nao encontrado no host."; exit 1; }
docker info >/dev/null 2>&1 || { echo "ERRO: daemon do docker nao esta acessivel."; exit 1; }

# O script oficial faz "rm -rf \$BUILD_ROOT": se BUILD_ROOT fosse o proprio
# bind-mount, o rm falharia com "device or resource busy". Por isso montamos
# o PARENT do build root, nunca o build root em si.
BUILD_PARENT="$(dirname "$BUILD_ROOT")"
mkdir -p "$BUILD_PARENT" "$CACHE_DIR"

echo "=== Build da distro em container ==="
echo "Imagem:      $IMAGE"
echo "TAG:         $TAG"
echo "Build root:  $BUILD_ROOT"
echo "Cache pacman:$CACHE_DIR"
echo "Projeto:     $PROJECT_ROOT (montado em /repo)"
echo ""

# --privileged: o arch-chroot precisa montar /proc, /sys, /dev e /run dentro do
# rootfs durante locale-gen/ssh-keygen/systemctl/mkinitcpio.
docker run --rm --privileged \
  -v "$PROJECT_ROOT:/repo" \
  -v "$BUILD_PARENT:$BUILD_PARENT" \
  -v "$CACHE_DIR:/var/cache/pacman/pkg" \
  "$IMAGE" bash -c '
set -euo pipefail
pacman -Sy --noconfirm --needed arch-install-scripts make binutils >/dev/null
cd /repo/distro
PS4_BUILD_ROOT="'"$BUILD_ROOT"'" ./01-build-image-7.0.sh "'"$TAG"'"
'

echo ""
echo "=== Build concluido ==="
echo "Artefatos por tag em distro/boot_referencia/:"
ls -la "$DISTRO_DIR/boot_referencia/" | grep -- "$TAG" || true
