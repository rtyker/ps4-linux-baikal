#!/bin/bash
# Executar no PC com HD montado (sda1 em /mnt/boot)
# Uso: ./02_preparar_teste.sh "720p" ou "1080p" ou "1080p_noforce" ou "1080p_poll"
set -euo pipefail

BOOT_MNT="${BOOT_MNT:-/run/media/anderson/BOOT}"
PC_IP="${PC_IP:-192.168.0.1}"
PS4_IP="${PS4_IP:-192.168.0.2}"
PC_MAC="${PC_MAC:-b4:45:06:6c:f6:4f}"

BASE="panic=0 clocksource=tsc consoleblank=0 net.ifnames=0 radeon.dpm=0 amdgpu.dpm=0 console=ttyS0,115200n8 console=tty0 quiet amdgpu.audio=1 usbcore.autosuspend=-1 amdgpu.gpu_recovery=1 mitigations=off zswap.enabled=1 systemd.unified_cgroup_hierarchy=0 systemd.legacy_systemd_cgroup_controller=yes"
NETCONSOLE="netconsole=6665@${PS4_IP}/eth0,6666@${PC_IP}/${PC_MAC}"
DEBUG="drm.debug=0x06 ignore_loglevel"

case "${1:-}" in
  720p)
    BOOTARGS="$BASE $DEBUG video=HDMI-A-1:1280x720@60e $NETCONSOLE"
    ;;
  1080p)
    BOOTARGS="$BASE $DEBUG video=HDMI-A-1:1920x1080@60e $NETCONSOLE"
    ;;
  1080p_noforce)
    BOOTARGS="$BASE $DEBUG video=HDMI-A-1:1920x1080@60 $NETCONSOLE"
    ;;
  1080p_poll)
    BOOTARGS="$BASE $DEBUG video=HDMI-A-1:1920x1080@60e drm_kms_helper.poll=1 $NETCONSOLE"
    ;;
  *)
    echo "Uso: $0 {720p|1080p|1080p_noforce|1080p_poll}"
    exit 1
    ;;
esac

echo "$BOOTARGS" > "$BOOT_MNT/bootargs.txt"
echo "=== Bootargs gravado em $BOOT_MNT/bootargs.txt ==="
echo "$BOOTARGS"
echo ""
echo "=== Próximo passo: sync && eject HD ==="
