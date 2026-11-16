#!/bin/bash
# build-full-20261113.sh — Orquestrador: kernel + rootfs + burn em /dev/sda
# Tag: 20261113-full-rebuild
# Uso: sudo bash build-full-20261113.sh < /dev/null > /tmp/build-full-20261113-full-rebuild.log 2>&1 &
#
# Sem set -e aqui: os scripts oficiais (00-build-kernel, build-image-docker,
# 02-burn-image) têm set -euo pipefail próprio e tratam seus erros internamente.
# O wrapper verifica exit codes explicitamente após cada etapa.
set -uo pipefail

TAG="20261113-full-rebuild"
ROOT="$(cd "$(dirname "$0")" && pwd)"
DEV="/dev/sda"

[ "$EUID" -eq 0 ] || { echo "ERRO: execute com sudo"; exit 1; }

ts() { date '+%Y-%m-%d %H:%M:%S'; }

echo "========================================================"
echo " PS4 Linux Baikal — Full rebuild: $TAG"
echo " Início: $(ts)"
echo " Device destino: $DEV"
echo "========================================================"

###############################################################################
# ETAPA 1 — Kernel (ccache clang, ThinLTO — via script oficial)
###############################################################################
echo ""
echo ">>> [$(ts)] ETAPA 1/3 — Build do kernel ($TAG)"
cd "$ROOT/kernel"
bash 00-build-kernel-7.0.sh "$TAG"
RC=$?
[ $RC -eq 0 ] || { echo "ERRO FATAL na ETAPA 1 (kernel) — exit $RC"; exit $RC; }
echo ">>> [$(ts)] ETAPA 1 CONCLUÍDA — bzImage gerado"

###############################################################################
# ETAPA 2 — Rootfs completo via Docker (sem --incremental)
###############################################################################
echo ""
echo ">>> [$(ts)] ETAPA 2/3 — Build do rootfs completo via Docker ($TAG)"
cd "$ROOT/distro"
bash scripts/build-image-docker.sh "$TAG"
RC=$?
[ $RC -eq 0 ] || { echo "ERRO FATAL na ETAPA 2 (rootfs) — exit $RC"; exit $RC; }
echo ">>> [$(ts)] ETAPA 2 CONCLUÍDA — rootfs tar gerado"

###############################################################################
# ETAPA 3 — Burn no /dev/sda
###############################################################################
echo ""
echo ">>> [$(ts)] ETAPA 3/3 — Burn no $DEV ($TAG)"
ROOTFS_TAR="${PS4_BUILD_ROOT:-/mnt/hdauxiliar/temp/arch_build_7.0}/arch_minimal_v2-7.0.tar"
[ -f "$ROOTFS_TAR" ] || ROOTFS_TAR="$ROOT/distro/arch_minimal_v2-7.0.tar"
echo ">>> Usando rootfs: $ROOTFS_TAR"
cd "$ROOT/distro"
bash 02-burn-image-7.0.sh "$DEV" "$ROOTFS_TAR" "$TAG"
RC=$?
[ $RC -eq 0 ] || { echo "ERRO FATAL na ETAPA 3 (burn) — exit $RC"; exit $RC; }
echo ">>> [$(ts)] ETAPA 3 CONCLUÍDA — burn em $DEV OK"

###############################################################################
# RESULTADO
###############################################################################
echo ""
echo "========================================================"
echo " FULL REBUILD CONCLUÍDO: $TAG"
echo " Fim: $(ts)"
echo " HD plugado ($DEV) pronto — pode desligar e levar para o PS4"
echo "========================================================"
