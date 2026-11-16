#!/bin/bash
# 02-burn-mesa.sh — Deploy Mesa drivers/libraries to PS4 target (analogous to 02-burn-image.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${1:-/mnt/hdauxiliar/toolchains/ps4/ps4-sdk/sysroot}"
ARTIFACTS_DIR="$SCRIPT_DIR/build_artifacts"

[ "$EUID" -eq 0 ] || { echo "Execute com sudo"; exit 1; }
[ -n "$TARGET_DIR" ] || { echo "ERRO: Forneça diretório alvo para deploy"; exit 1; }
[ -d "$ARTIFACTS_DIR" ] || { echo "ERRO: Artefatos não encontrados em $ARTIFACTS_DIR"; exit 1; }

echo "=== Burning Mesa drivers/libraries to target: $TARGET_DIR ==="

# Ensure target directory exists
mkdir -p "$TARGET_DIR"

# Copy Mesa libraries
echo "=== Deploying Mesa GL/Vulkan libraries ==="
rsync -av "$ARTIFACTS_DIR/" "$TARGET_DIR/"

# Ensure directory structure for dri/ld.so.cache
echo "=== Building dri/glvnd artifact cache ==="
mkdir -p "$TARGET_DIR/etc/dri"
mkdir -p "$TARGET_DIR/etc/ld.so.conf.d"

# Create basic dri search path config (for PS4 target apps)
cat > "$TARGET_DIR/etc/ld.so.conf.d/mesa-gl.conf" << 'LDCONF'
/usr/lib
/usr/lib32
/usr/lib64
LDCONF

# Optional: If drirc exists but empty, skip
echo "=== Mesa deployment completed successfully ==="
echo "Target: $TARGET_DIR"
echo "Mesa version: 26.1.5 (custom PS4 Gladius/Liverpool)"

# Summary of deployed files
find "$TARGET_DIR" -maxdepth 3 \( -name "*.so*" -o -name "*.json" \) -printf "Artifact: %p\n" | sort
