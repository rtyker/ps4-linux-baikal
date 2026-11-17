#!/bin/bash
# deploy-boot-ftp-7.0.sh <TAG> [opcoes] — grava o boot de uma tag no disco INTERNO do PS4 por FTP.
#
# Caminho alternativo ao deploy-boot-7.0.sh (que escreve no USB e NAO e tocado por este script).
# O payload procura bzImage, initramfs.cpio.gz, bootargs.txt e vram.txt, um a um, em /mnt/usb0,
# /mnt/usb1, /data/linux/boot e /user/system/boot. Este script mantem os 4 em /data/linux/boot.
# Detalhes e cuidados: others/docs/BOOT_PELO_DISCO_INTERNO.md
#
# Requisitos: o PS4 em modo ORBIS com o FTP do GoldHEN (porta 2121) ativo; curl e md5sum no host.
# NUNCA faz probe na porta 9090 (o BinLoader tem accept() unico).
#
# Seguranca: tudo sobe com nome temporario (.part), e conferido por md5 baixando de volta, e so
# depois e renomeado para o nome final. Se qualquer arquivo falhar, nada final e alterado.
# Antes de sobrescrever, os arquivos que ja estao no PS4 sao baixados para um backup no host.
#
# Uso:
#   ./deploy-boot-ftp-7.0.sh <TAG> [--vram MB] [--ip IP] [--port N] [--no-marker] [--dry-run]
#                                  [--allow-usb-conflict]
#   --vram MB             grava tambem vram.txt (32..4096). Sem esta opcao o vram.txt do PS4 nao e tocado
#   --no-marker           nao acrescenta bootsrc=internal ao bootargs (por padrao acrescenta)
#   --allow-usb-conflict  segue mesmo se o USB tiver arquivos de boot (o USB tem prioridade!)
#   --dry-run             so mostra o que faria; nao escreve nada no PS4
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

die() { echo "ERRO: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --vram)  VRAM="${2:-}"; shift 2 ;;
    --ip)    IP="${2:-}"; shift 2 ;;
    --port)  PORT="${2:-}"; shift 2 ;;
    --no-marker) MARKER=0; shift ;;
    --allow-usb-conflict) ALLOW_USB=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n 2,26p "$0"; exit 0 ;;
    -*) die "opcao desconhecida: $1" ;;
    *) [ -z "$TAG" ] || die "tag duplicada: $1"; TAG="$1"; shift ;;
  esac
done
[ -n "$TAG" ] || die "uso: $0 <TAG> [--vram MB] [--ip IP] [--no-marker] [--dry-run]"

command -v curl >/dev/null || die "curl nao encontrado"
command -v md5sum >/dev/null || die "md5sum nao encontrado"

if [ -n "$VRAM" ]; then
  case "$VRAM" in
    32|64|128|256|512|1024|2048|2560|3072|4096) ;;
    *) die "--vram invalido ($VRAM). Valores aceitos pelo payload: 32 64 128 256 512 1024 2048 2560 3072 4096" ;;
  esac
fi

SRC_KERNEL="$BOOT_DIR/bzImage-7.0-$TAG"
SRC_ARGS="$BOOT_DIR/bootargs-7.0-$TAG.txt"
SRC_INITRD="$BOOT_DIR/initramfs-7.0-$TAG.cpio.gz"
for f in "$SRC_KERNEL" "$SRC_ARGS" "$SRC_INITRD"; do
  [ -s "$f" ] || die "arquivo da tag ausente ou vazio: $f"
done

FTP="ftp://$IP:$PORT"
CURL=(curl -s --max-time 120)

echo "=== deploy-boot-ftp: tag $TAG -> $IP:$PORT$REMOTE_DIR ==="

# 1. FTP reachable (only exists while the PS4 runs Orbis)
if ! "${CURL[@]}" --max-time 15 "$FTP/data/linux/" >/dev/null 2>&1; then
  die "FTP $IP:$PORT nao responde. O FTP so existe no modo Orbis (antes do kexec). Carregue o GoldHEN e tente de novo."
fi
echo "  OK   FTP responde"

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

echo "--- arquivos a enviar (md5 local)"
for n in "${NAMES[@]}"; do
  printf '  %-20s %10s bytes  md5 %s\n' "$n" "$(stat -c %s "$WORK/$n")" "$(md5sum < "$WORK/$n" | cut -c1-12)"
done
[ -n "$VRAM" ] || echo "  (vram.txt do PS4 nao sera tocado; use --vram MB para gravar)"

# 4. USB conflict: files on the USB win over the internal ones
echo "--- conflito com o USB (o USB tem prioridade sobre o interno)"
CONFLICT=0
for u in usb0 usb1; do
  listing="$("${CURL[@]}" --max-time 15 "$FTP/mnt/$u/" 2>/dev/null || true)"
  for n in bzImage initramfs.cpio.gz bootargs.txt vram.txt; do
    if printf '%s\n' "$listing" | grep -qE " $n\$"; then
      echo "  AVISO: /mnt/$u/$n existe e sera usado NO LUGAR do interno"
      CONFLICT=1
    fi
  done
done
if [ "$CONFLICT" = 1 ] && [ "$ALLOW_USB" = 0 ]; then
  die "o USB tem arquivos de boot. Remova-os do USB (BOOT) ou use --allow-usb-conflict."
fi
[ "$CONFLICT" = 1 ] || echo "  OK   nenhum arquivo de boot no USB (ou o USB nao esta visivel)"

if [ "$DRY" = 1 ]; then
  echo "=== --dry-run: nada foi escrito no PS4 ==="
  exit 0
fi

# 5. backup of what is already in the PS4
BK="$HOME/ps4-boot-internal-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BK"
HAVE_OLD=0
REMOTE_LIST="$("${CURL[@]}" "$FTP$REMOTE_DIR/" 2>/dev/null || true)"
for n in "${NAMES[@]}" active-tag.txt; do
  if printf '%s\n' "$REMOTE_LIST" | grep -qE " $n\$"; then
    "${CURL[@]}" -o "$BK/$n" "$FTP$REMOTE_DIR/$n" && HAVE_OLD=1
  fi
done
if [ "$HAVE_OLD" = 1 ]; then echo "--- backup dos arquivos que ja estavam no PS4: $BK"; else rmdir "$BK"; echo "--- nada para fazer backup em $REMOTE_DIR"; fi

# 6. upload every file under a temporary name and verify it before touching any final name
echo "--- upload (.part) e conferencia md5"
for n in "${NAMES[@]}" active-tag.txt; do
  "${CURL[@]}" --ftp-create-dirs -T "$WORK/$n" "$FTP$REMOTE_DIR/$n.part" || die "falha no upload de $n"
  "${CURL[@]}" -o "$WORK/check.$n" "$FTP$REMOTE_DIR/$n.part" || die "falha ao baixar $n.part para conferir"
  a="$(md5sum < "$WORK/$n" | cut -c1-32)"; b="$(md5sum < "$WORK/check.$n" | cut -c1-32)"
  if [ "$a" != "$b" ]; then
    for m in "${NAMES[@]}" active-tag.txt; do "${CURL[@]}" -Q "-DELE $m.part" "$FTP$REMOTE_DIR/" >/dev/null 2>&1 || true; done
    die "md5 de $n difere depois do upload ($a contra $b). Nada final foi alterado."
  fi
  printf '  OK   %-20s md5 %s\n' "$n" "${a:0:12}"
done

# 7. rename everything into place (initramfs and kernel first, bootargs last)
echo "--- renomeando para os nomes finais"
for n in "${NAMES[@]}" active-tag.txt; do
  "${CURL[@]}" -Q "-RNFR $n.part" -Q "-RNTO $n" "$FTP$REMOTE_DIR/" >/dev/null || die "rename de $n falhou (os .part ficaram no PS4)"
done

# 8. final check: download the final names and compare again
echo "--- conferencia final (nomes finais)"
FAIL=0
for n in "${NAMES[@]}"; do
  "${CURL[@]}" -o "$WORK/final.$n" "$FTP$REMOTE_DIR/$n" || { echo "  FALHA ao baixar $n"; FAIL=1; continue; }
  a="$(md5sum < "$WORK/$n" | cut -c1-32)"; b="$(md5sum < "$WORK/final.$n" | cut -c1-32)"
  if [ "$a" = "$b" ]; then printf '  OK   %-20s md5 %s\n' "$n" "${a:0:12}"; else echo "  FALHA $n: $a contra $b"; FAIL=1; fi
done
leftover="$("${CURL[@]}" "$FTP$REMOTE_DIR/" | grep -c '\.part$' || true)"
[ "$leftover" = 0 ] || { echo "  AVISO: $leftover arquivo(s) .part sobraram em $REMOTE_DIR"; FAIL=1; }
[ "$FAIL" = 0 ] || die "a conferencia final falhou; confira $REMOTE_DIR antes de dar boot"

echo "=== deploy-boot-ftp concluido: $TAG esta em $REMOTE_DIR ==="
echo "Depois do boot, confira: grep $MARKER_TOKEN /proc/cmdline"
