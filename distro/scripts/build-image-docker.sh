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
#   sudo ./scripts/build-image-docker.sh <TAG>                  # build limpo
#   sudo ./scripts/build-image-docker.sh <TAG> --incremental    # reutiliza rootfs
#
# O --incremental é repassado ao script oficial: pula rm -rf + pacstrap e usa o
# rootfs já existente em PS4_BUILD_ROOT (útil quando só o kernel/bzImage mudou).
#
# Env:
#   PS4_BUILD_IMAGE   imagem base (default: archlinux:latest)
#   PS4_BUILD_ROOT    area de build (default: /mnt/hdauxiliar/temp/arch_build_7.0)
#   PS4_BUILD_CACHE   cache do pacman compartilhado (default: /mnt/hdauxiliar/temp/pacman-cache)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISTRO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$DISTRO_DIR/.." && pwd)"

TAG="${1:?Uso: $0 <TAG> [--incremental]}"
INCREMENTAL="${2:-}"
IMAGE="${PS4_BUILD_IMAGE:-archlinux:latest}"
BUILD_ROOT="${PS4_BUILD_ROOT:-$PROJECT_ROOT/arch_build_7.0}"
CACHE_DIR="${PS4_BUILD_CACHE:-$PROJECT_ROOT/pacman-cache}"

# O build pode rodar em qualquer disco com suporte a montagem/chroot.
case "$BUILD_ROOT" in
  /mnt/t|/mnt/t/*)
    echo "AVISO: BUILD_ROOT em $BUILD_ROOT — verifique se suporta chroot/mount."
    ;;
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
INCREMENTAL_FLAG=""
[ -n "$INCREMENTAL" ] && INCREMENTAL_FLAG="--incremental"

docker run --rm --privileged \
  -v "$PROJECT_ROOT:/repo" \
  -v "$BUILD_PARENT:$BUILD_PARENT" \
  -v "$CACHE_DIR:/var/cache/pacman/pkg" \
  -e PS4_BUILD_ROOT="$BUILD_ROOT" \
  "$IMAGE" bash -c '
set -euo pipefail
pacman -Sy --noconfirm --needed arch-install-scripts make binutils >/dev/null
cd /repo/distro
exec ./01-build-image-7.0.sh "$@"
' _ "$TAG" "$INCREMENTAL_FLAG"

echo ""
echo "=== Build concluido ==="
COMPLETE_MARKER="$DISTRO_DIR/boot_referencia/.build-complete-$TAG"
if [ -f "$COMPLETE_MARKER" ]; then
  echo "✅ Build concluído com sucesso (sentinela encontrada: $COMPLETE_MARKER)"
else
  echo "⚠️  Build terminou mas sentinela não encontrada — verificar manualmente"
fi
echo "Artefatos por tag em distro/boot_referencia/:"
ls -la "$DISTRO_DIR/boot_referencia/" | grep -- "$TAG" || true
