#!/bin/bash
# fetch-internal-boot.sh <TAG> [--ip IP] [--port N] [--out-dir DIR]
# Downloads the 4 boot files (bzImage, initramfs.cpio.gz, bootargs.txt, vram.txt)
# from the PS4's INTERNAL disk (/data/linux/boot/) via FTP (Orbis mode).
# Saves them as the tag's reference files in boot_referencia/ (or custom out-dir).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT_DIR="${PS4_BOOT_REF:-$SCRIPT_DIR/../../distro/boot_referencia}"

TAG=""
IP="${PS4_ORBIS_IP:-192.168.6.130}"
PORT="${PS4_FTP_PORT:-2121}"
OUT_DIR="$BOOT_DIR"
REMOTE_DIR="/data/linux/boot"

die() { echo "ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --ip)    IP="${2:-}"; shift 2 ;;
    --port)  PORT="${2:-}"; shift 2 ;;
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) sed -n 2,12p "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$TAG" ] || die "duplicate tag: $1"; TAG="$1"; shift ;;
  esac
done
[ -n "$TAG" ] || die "usage: $0 <TAG> [--ip IP] [--port N] [--out-dir DIR]"

command -v curl >/dev/null || die "curl not found"

FTP="ftp://$IP:$PORT"
CURL=(curl -s --max-time 60)

echo "=== fetch-internal-boot: $IP:$PORT$REMOTE_DIR -> tag $TAG ==="

# 1. FTP reachable
if ! "${CURL[@]}" --max-time 15 "$FTP/data/linux/" >/dev/null 2>&1; then
  die "FTP $IP:$PORT is not answering. FTP only exists in Orbis mode (before the kexec). Load GoldHEN and try again."
fi
echo "  OK   FTP is answering"

# 2. work area
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 3. list remote dir
REMOTE_LIST="$("${CURL[@]}" "$FTP$REMOTE_DIR/" 2>/dev/null || true)"
if [ -z "$REMOTE_LIST" ]; then
  die "could not list $REMOTE_DIR"
fi

# 4. download each expected file
NAMES=(bzImage initramfs.cpio.gz bootargs.txt vram.txt active-tag.txt)
HAVE_ANY=0
for n in "${NAMES[@]}"; do
  if printf '%s\n' "$REMOTE_LIST" | grep -qE " $n\$"; then
    echo "  downloading $n..."
    "${CURL[@]}" -o "$WORK/$n" "$FTP$REMOTE_DIR/$n" || die "download of $n failed"
    HAVE_ANY=1
  else
    echo "  WARNING: $n not found in $REMOTE_DIR"
  fi
done
[ "$HAVE_ANY" = 1 ] || die "no boot files found in $REMOTE_DIR"

# 5. ensure output dir exists
mkdir -p "$OUT_DIR"

# 6. copy to boot_referencia with tag suffix
for n in bzImage initramfs.cpio.gz bootargs.txt vram.txt; do
  if [ -f "$WORK/$n" ]; then
    case "$n" in
      bzImage)          dst="$OUT_DIR/bzImage-7.0-$TAG" ;;
      initramfs.cpio.gz) dst="$OUT_DIR/initramfs-7.0-$TAG.cpio.gz" ;;
      bootargs.txt)      dst="$OUT_DIR/bootargs-7.0-$TAG.txt" ;;
      vram.txt)          dst="$OUT_DIR/vram-7.0-$TAG.txt" ;;
    esac
    cp "$WORK/$n" "$dst"
    echo "  saved: $dst ($(stat -c %s "$dst") bytes, md5 $(md5sum < "$dst" | cut -c1-12))"
  fi
done

# 7. if active-tag.txt exists, show it
if [ -f "$WORK/active-tag.txt" ]; then
  echo "  active-tag on PS4: $(cat "$WORK/active-tag.txt")"
fi

echo "=== fetch-internal-boot finished: tag $TAG files in $OUT_DIR ==="