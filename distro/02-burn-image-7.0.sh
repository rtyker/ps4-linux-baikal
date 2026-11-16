#!/bin/bash
# 02-burn-image-7.0.sh /dev/sdX [ROOTFS_TAR] [TAG] — Grava Arch Minimal v2 kernel 7.0 no HD
#
# Reescreve o HD inteiro: particiona, formata (BOOT=vfat / psxitarch=ext4) e
# grava boot + rootfs. O NOME DA PARTIÇÃO DO ROOTFS É OBRIGATORIO: "psxitarch"
# (o initramfs do busybox faz mount LABEL=psxitarch — outro label = boot no
# rescue shell).
#
# Os artefatos de boot são lidos POR TAG em boot_referencia/ (mesmo contrato do
# deploy-boot-7.0.sh e do promote-release.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOT_REF="${PS4_BOOT_REF:-$SCRIPT_DIR/boot_referencia}"
DEV="${1:-/dev/sda}"
ROOTFS_TAR="${2:-$SCRIPT_DIR/arch_minimal_v2-7.0.tar}"
TAG="${3:-${TAG:-}}"

# REGRA CRÍTICA (AGENTS.md): NUNCA montar diretamente em /mnt — sempre em um
# subdiretório dedicado, para não colidir com outros mounts do sistema.
BURN_MNT="${PS4_BURN_MNT:-/mnt/ps4_burn_7.0}"

[ "$EUID" -eq 0 ] || { echo "Execute com sudo"; exit 1; }
[ -b "$DEV" ] || { echo "$DEV nao encontrado"; exit 1; }
[ -f "$ROOTFS_TAR" ] || { echo "Rootfs $ROOTFS_TAR nao encontrado"; exit 1; }

if [ -z "$TAG" ]; then
  mapfile -t _TAGS < <(cd "$BOOT_REF" 2>/dev/null && ls -1 bzImage-7.0-* 2>/dev/null | sed 's/^bzImage-7\.0-//')
  case "${#_TAGS[@]}" in
    0) echo "ERRO: nenhuma tag em $BOOT_REF e nenhum TAG informado."; exit 1 ;;
    1) TAG="${_TAGS[0]}"; echo "=== TAG autodetectada: $TAG ===" ;;
    *) echo "ERRO: multiplas tags em $BOOT_REF — informe a tag: $0 $DEV <ROOTFS_TAR> <TAG>"; exit 1 ;;
  esac
fi

BZIMAGE="$BOOT_REF/bzImage-7.0-$TAG"
INITRAMFS="$BOOT_REF/initramfs-7.0-$TAG.cpio.gz"
BOOTARGS="$BOOT_REF/bootargs-7.0-$TAG.txt"

[ -f "$BZIMAGE" ]   || { echo "Kernel 7.0 ($BZIMAGE) nao encontrado"; exit 1; }
[ -f "$INITRAMFS" ] || { echo "Initramfs 7.0 ($INITRAMFS) nao encontrado"; exit 1; }
[ -f "$BOOTARGS" ]  || { echo "Bootargs 7.0 ($BOOTARGS) nao encontrado"; exit 1; }
# vram.txt é genérico (não versionado por tag): se não existir, cria com o mesmo
# default do deploy-boot-7.0.sh (1024 MB) em vez de abortar o burn.
VRAM_FILE="$BOOT_REF/vram.txt"
if [ ! -f "$VRAM_FILE" ]; then
  echo "vram.txt ausente — criando com o default (1024)."
  echo "1024" > "$VRAM_FILE"
fi

# O tar do rootfs é GENÉRICO (não é versionado por tag): o mesmo tar serve a
# várias tags. Mas se o kernel da tag for mais novo que o rootfs, o que vai
# pro HD é uma mistura de dois builds — o sintoma clássico é "o kernel novo não
# acha o módulo do driver". Aviso alto (não bloqueia: reusar um rootfs é
# prática normal e legítima).
if [ "$BZIMAGE" -nt "$ROOTFS_TAR" ]; then
  echo
  echo "AVISO: o bzImage da tag ($TAG) é MAIS NOVO que o rootfs tar:"
  echo "         bzImage: $(date -r "$BZIMAGE" '+%Y-%m-%d %H:%M')"
  echo "         rootfs:  $(date -r "$ROOTFS_TAR" '+%Y-%m-%d %H:%M')"
  echo "         O rootfs gravado pode não corresponder a esta tag."
  echo "         Se for o caso, rode 01-build-image-7.0.sh $TAG antes de gravar."
  echo
fi

BOOT="${DEV}1"
ROOT="${DEV}2"

echo "=== Desmontando partições antigas ==="
umount -l "$BOOT" 2>/dev/null || true
umount -l "$ROOT" 2>/dev/null || true
umount -l "$BURN_MNT/boot" 2>/dev/null || true
umount -l "$BURN_MNT/root" 2>/dev/null || true
umount -l "$BURN_MNT" 2>/dev/null || true

echo "=== Particionando $DEV (kernel 7.0) ==="
fdisk "$DEV" <<EOF
o
n
p
1

+200M
t
b
a
1
n
p
2


w
EOF

partprobe "$DEV" || sleep 1
udevadm settle 2>/dev/null || true

# udisks2 remonta automaticamente as partições assim que a nova tabela
# aparece (antes do mkfs rodar) - desmontar de novo defensivamente
sleep 1
umount -l "$BOOT" 2>/dev/null || true
umount -l "$ROOT" 2>/dev/null || true

echo "=== Formatando ==="
mkfs.vfat -F 32 "$BOOT" -n BOOT
umount -l "$ROOT" 2>/dev/null || true
mkfs.ext4 -q -F -L psxitarch "$ROOT"

echo "=== Montando (em $BURN_MNT — nunca direto em /mnt) ==="
mkdir -p "$BURN_MNT/boot" "$BURN_MNT/root"
mount "$BOOT" "$BURN_MNT/boot"
mount "$ROOT" "$BURN_MNT/root"

echo "=== Copiando boot (kernel 7.0, tag $TAG) ==="
cp "$BZIMAGE"   "$BURN_MNT/boot/bzImage"
cp "$INITRAMFS" "$BURN_MNT/boot/initramfs.cpio.gz"
cp "$BOOTARGS"  "$BURN_MNT/boot/bootargs.txt"
cp "$BOOT_REF/vram.txt" "$BURN_MNT/boot/vram.txt"
touch "$BURN_MNT/boot/bootlog.txt"
echo "$TAG" > "$BURN_MNT/boot/active-tag.txt"

echo "=== Extraindo rootfs (numeric-owner) ==="
tar -xpf "$ROOTFS_TAR" -C "$BURN_MNT/root" --numeric-owner
sync

echo "=== Desmontando ==="
umount "$BURN_MNT/root" "$BURN_MNT/boot"

echo "=== Concluido (kernel 7.0, tag $TAG) ==="
echo "Desconecte o HD, conecte no PS4, envie payload via Payload Guest"
echo "Login: ps4 / ps4"