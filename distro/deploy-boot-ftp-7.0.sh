#!/bin/bash
# deploy-boot-ftp-7.0.sh <TAG> [options] - writes a tag's boot files to the PS4's INTERNAL disk over FTP.
#
# Alternative to deploy-boot-7.0.sh (which writes to the USB drive and is NOT touched by this script).
# The payload looks for bzImage, initramfs.cpio.gz, bootargs.txt and vram.txt, one by one, in
# /mnt/usb0, /mnt/usb1, /data/linux/boot and /user/system/boot. This script keeps all four in
# /data/linux/boot.
# Details and caveats: others/docs/BOOT_FROM_INTERNAL_DISK.md
#
# Requirements: the PS4 in ORBIS mode with the GoldHEN FTP server (port 2121) running; curl and
# md5sum on the host. It NEVER probes port 9090 (the BinLoader has a single accept()).
#
# Safety: everything is uploaded under a temporary name (.part), verified by md5 after downloading
# it back, and only then renamed to its final name. If any file fails, no final file is changed.
# Before overwriting, whatever is already on the PS4 is downloaded to a backup folder on the host.
#
# Usage:
#   ./deploy-boot-ftp-7.0.sh <TAG> [--vram MB] [--ip IP] [--port N] [--no-marker] [--dry-run]
#                                  [--allow-usb-conflict]
#   --vram MB             also writes vram.txt (32..4096). Without it the PS4's vram.txt is left alone
#   --no-marker           do not append bootsrc=internal to bootargs (it is appended by default)
#   --allow-usb-conflict  go on even if the USB drive has boot files (the USB drive wins!)
#   --dry-run             only show what would be done; nothing is written to the PS4
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT_DIR="${PS4_BOOT_REF:-$SCRIPT_DIR/boot_referencia}"

TAG=""
IP="${PS4_ORBIS_IP:-192.168.6.130}"
PORT="${PS4_FTP_PORT:-2121}"
VRAM=""
MARKER=1
DRY=0
ALLOW_USB=0
REMOTE_DIR="/data/linux/boot"
MARKER_TOKEN="bootsrc=internal"

die() { echo "ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --vram)  VRAM="${2:-}"; shift 2 ;;
    --ip)    IP="${2:-}"; shift 2 ;;
    --port)  PORT="${2:-}"; shift 2 ;;
    --no-marker) MARKER=0; shift ;;
    --allow-usb-conflict) ALLOW_USB=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n 2,24p "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$TAG" ] || die "duplicate tag: $1"; TAG="$1"; shift ;;
  esac
done
[ -n "$TAG" ] || die "usage: $0 <TAG> [--vram MB] [--ip IP] [--no-marker] [--dry-run]"

command -v curl >/dev/null || die "curl not found"
command -v md5sum >/dev/null || die "md5sum not found"

if [ -n "$VRAM" ]; then
  case "$VRAM" in
    32|64|128|256|512|1024|2048|2560|3072|4096) ;;
    *) die "invalid --vram ($VRAM). Values accepted by the payload: 32 64 128 256 512 1024 2048 2560 3072 4096" ;;
  esac
fi

SRC_KERNEL="$BOOT_DIR/bzImage-7.0-$TAG"
SRC_ARGS="$BOOT_DIR/bootargs-7.0-$TAG.txt"
SRC_INITRD="$BOOT_DIR/initramfs-7.0-$TAG.cpio.gz"
for f in "$SRC_KERNEL" "$SRC_ARGS" "$SRC_INITRD"; do
  [ -s "$f" ] || die "tag file missing or empty: $f"
done

FTP="ftp://$IP:$PORT"
CURL=(curl -s --max-time 120)

echo "=== deploy-boot-ftp: tag $TAG -> $IP:$PORT$REMOTE_DIR ==="

# 1. FTP reachable (only exists while the PS4 runs Orbis)
if ! "${CURL[@]}" --max-time 15 "$FTP/data/linux/" >/dev/null 2>&1; then
  die "FTP $IP:$PORT is not answering. FTP only exists in Orbis mode (before the kexec). Load GoldHEN and try again."
fi
echo "  OK   FTP is answering"

# 2. work area on the host
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 3. bootargs with the proof marker
tr -d '\n' < "$SRC_ARGS" > "$WORK/bootargs.txt"
if [ "$MARKER" = 1 ] && ! grep -q "$MARKER_TOKEN" "$WORK/bootargs.txt"; then
  printf ' %s' "$MARKER_TOKEN" >> "$WORK/bootargs.txt"
fi
printf '\n' >> "$WORK/bootargs.txt"

cp "$SRC_KERNEL" "$WORK/bzImage"
cp "$SRC_INITRD" "$WORK/initramfs.cpio.gz"
NAMES=(initramfs.cpio.gz bzImage bootargs.txt)
if [ -n "$VRAM" ]; then
  printf '%s\n' "$VRAM" > "$WORK/vram.txt"
  NAMES+=(vram.txt)
fi
printf '%s\n' "$TAG" > "$WORK/active-tag.txt"

echo "--- files to upload (local md5)"
for n in "${NAMES[@]}"; do
  printf '  %-20s %10s bytes  md5 %s\n' "$n" "$(stat -c %s "$WORK/$n")" "$(md5sum < "$WORK/$n" | cut -c1-12)"
done
[ -n "$VRAM" ] || echo "  (the PS4's vram.txt will not be touched; use --vram MB to write it)"

# 4. USB conflict: files on the USB drive win over the internal ones
echo "--- USB conflict check (the USB drive has priority over the internal disk)"
CONFLICT=0
for u in usb0 usb1; do
  listing="$("${CURL[@]}" --max-time 15 "$FTP/mnt/$u/" 2>/dev/null || true)"
  for n in bzImage initramfs.cpio.gz bootargs.txt vram.txt; do
    if printf '%s\n' "$listing" | grep -qE " $n\$"; then
      echo "  WARNING: /mnt/$u/$n exists and will be used INSTEAD of the internal one"
      CONFLICT=1
    fi
  done
done
if [ "$CONFLICT" = 1 ] && [ "$ALLOW_USB" = 0 ]; then
  die "the USB drive has boot files. Remove them from the USB (BOOT) or use --allow-usb-conflict."
fi
[ "$CONFLICT" = 1 ] || echo "  OK   no boot files on the USB drive (or the USB drive is not visible)"

if [ "$DRY" = 1 ]; then
  echo "=== --dry-run: nothing was written to the PS4 ==="
  exit 0
fi

# 5. backup of what is already on the PS4
BK="$HOME/ps4-boot-internal-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BK"
HAVE_OLD=0
REMOTE_LIST="$("${CURL[@]}" "$FTP$REMOTE_DIR/" 2>/dev/null || true)"
for n in "${NAMES[@]}" active-tag.txt; do
  if printf '%s\n' "$REMOTE_LIST" | grep -qE " $n\$"; then
    "${CURL[@]}" -o "$BK/$n" "$FTP$REMOTE_DIR/$n" && HAVE_OLD=1
  fi
done
if [ "$HAVE_OLD" = 1 ]; then echo "--- backup of the files already on the PS4: $BK"; else rmdir "$BK"; echo "--- nothing to back up in $REMOTE_DIR"; fi

# 6. upload every file under a temporary name and verify it before touching any final name
echo "--- upload (.part) and md5 check"
for n in "${NAMES[@]}" active-tag.txt; do
  "${CURL[@]}" --ftp-create-dirs -T "$WORK/$n" "$FTP$REMOTE_DIR/$n.part" || die "upload of $n failed"
  "${CURL[@]}" -o "$WORK/check.$n" "$FTP$REMOTE_DIR/$n.part" || die "could not download $n.part to verify it"
  a="$(md5sum < "$WORK/$n" | cut -c1-32)"; b="$(md5sum < "$WORK/check.$n" | cut -c1-32)"
  if [ "$a" != "$b" ]; then
    for m in "${NAMES[@]}" active-tag.txt; do "${CURL[@]}" -Q "-DELE $m.part" "$FTP$REMOTE_DIR/" >/dev/null 2>&1 || true; done
    die "md5 of $n differs after the upload ($a vs $b). No final file was changed."
  fi
  printf '  OK   %-20s md5 %s\n' "$n" "${a:0:12}"
done

# 7. rename everything into place (initramfs and kernel first, bootargs last)
echo "--- renaming to the final names"
for n in "${NAMES[@]}" active-tag.txt; do
  "${CURL[@]}" -Q "-RNFR $n.part" -Q "-RNTO $n" "$FTP$REMOTE_DIR/" >/dev/null || die "rename of $n failed (the .part files were left on the PS4)"
done

# 8. final check: download the final names and compare again
echo "--- final check (final names)"
FAIL=0
for n in "${NAMES[@]}"; do
  "${CURL[@]}" -o "$WORK/final.$n" "$FTP$REMOTE_DIR/$n" || { echo "  FAILED to download $n"; FAIL=1; continue; }
  a="$(md5sum < "$WORK/$n" | cut -c1-32)"; b="$(md5sum < "$WORK/final.$n" | cut -c1-32)"
  if [ "$a" = "$b" ]; then printf '  OK   %-20s md5 %s\n' "$n" "${a:0:12}"; else echo "  FAILED $n: $a vs $b"; FAIL=1; fi
done
leftover="$("${CURL[@]}" "$FTP$REMOTE_DIR/" | grep -c '\.part$' || true)"
[ "$leftover" = 0 ] || { echo "  WARNING: $leftover .part file(s) were left in $REMOTE_DIR"; FAIL=1; }
[ "$FAIL" = 0 ] || die "the final check failed; inspect $REMOTE_DIR before booting"

echo "=== deploy-boot-ftp finished: $TAG is in $REMOTE_DIR ==="
echo "After the boot, check: grep $MARKER_TOKEN /proc/cmdline"
