#!/bin/bash
# Executar no PC após conectar HD de volta (sda2 em /mnt/root)
set -euo pipefail

ROOT_MNT="${ROOT_MNT:-/mnt/ps4_root}"
LOG_DIR="$HOME/ps4_logs/disco_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

# Tentar montar se não estiver montado
if ! mountpoint -q "$ROOT_MNT"; then
  echo "Montando /dev/sda2 em $ROOT_MNT..."
  sudo mount /dev/sda2 "$ROOT_MNT" 2>/dev/null || true
fi

for f in dmesg_drm.log dmesg_errors.log dmesg_full.log boot_summary.log dmesg_net.log journal_last.log; do
  if [ -f "$ROOT_MNT/var/log/boot_debug/$f" ]; then
    cp "$ROOT_MNT/var/log/boot_debug/$f" "$LOG_DIR/"
    echo "✅ Copiado: $f"
  else
    echo "❌ Não encontrado: $f"
  fi
done

echo ""
echo "=== Logs salvos em: $LOG_DIR ==="
echo "=== DRM Log (primeiras 50 linhas): ==="
head -50 "$LOG_DIR/dmesg_drm.log" 2>/dev/null || echo "(vazio)"
