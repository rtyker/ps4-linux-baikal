#!/bin/bash
# deploy-boot-7.0.sh <TAG> — Troca apenas os arquivos de boot (sda1) no HD já
# particionado, SEM tocar no rootfs (sda2). Usa os arquivos versionados em
# boot_referencia/*-7.0-<TAG>* e os renomeia para os nomes genéricos
# (bzImage, bootargs.txt, initramfs.cpio.gz) SOMENTE dentro do HD de destino.
#
# Isso permite manter várias builds/variantes lado a lado em boot_referencia/
# (bzImage-7.0-<tag>, config-7.0-<tag>, bootargs-7.0-<tag>.txt) e escolher
# qual delas vira a "ativa" no HD a cada teste.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOT_REF="$SCRIPT_DIR/boot_referencia"
TAG="${1:?Uso: $0 <TAG> [ponto_de_montagem_boot]}"
BOOT_MNT="${2:-}"

BZIMAGE="$BOOT_REF/bzImage-7.0-$TAG"
CONFIG="$BOOT_REF/config-7.0-$TAG"
BOOTARGS="$BOOT_REF/bootargs-7.0-$TAG.txt"
# initramfs SEMPRE por tag. Não há fallback silencioso para o genérico
# initramfs-7.0.cpio.gz: em 2026-07-21 constatamos que ele diverge do que está
# realmente em uso (14MB de 16/jul vs 9.4MB da tag 20260720-sky2len-fix), então
# um deploy que caísse no fallback trocaria DUAS variáveis de uma vez (kernel +
# initramfs) sem avisar. Num ciclo em que cada teste custa um power cycle
# completo, isso vale uma sessão inteira de conclusões erradas.
# Para reusar o initramfs de outra tag, copie EXPLICITAMENTE:
#   cp boot_referencia/initramfs-7.0-<tag_origem>.cpio.gz \
#      boot_referencia/initramfs-7.0-<tag_nova>.cpio.gz
INITRAMFS="$BOOT_REF/initramfs-7.0-$TAG.cpio.gz"

[ -f "$BZIMAGE" ]  || { echo "ERRO: $BZIMAGE não encontrado"; exit 1; }
[ -f "$BOOTARGS" ] || { echo "ERRO: $BOOTARGS não encontrado"; exit 1; }
if [ ! -f "$INITRAMFS" ]; then
  echo "ERRO: $INITRAMFS não encontrado."
  echo
  echo "Toda tag precisa do seu próprio initramfs — não usamos mais o genérico"
  echo "como fallback, para não trocar initramfs sem você perceber."
  echo
  echo "Opções:"
  echo "  a) reusar o de outra tag (o caso comum, quando só o kernel mudou):"
  echo "       cp $BOOT_REF/initramfs-7.0-<tag_origem>.cpio.gz \\"
  echo "          $INITRAMFS"
  echo "  b) gerar um novo: ./rebuild-initramfs-7.0.sh   (ou 01-build-image-7.0.sh)"
  echo
  echo "  Disponíveis:"
  ls -1 "$BOOT_REF"/initramfs-7.0*.cpio.gz 2>/dev/null | sed 's|^|    |' || echo "    (nenhum)"
  exit 1
fi

# --- Auto-detectar partição BOOT montada, se não informado ---
if [ -z "$BOOT_MNT" ]; then
  BOOT_MNT=$(lsblk -no MOUNTPOINT,LABEL | awk '$2=="BOOT"{print $1; exit}')
fi

[ -n "$BOOT_MNT" ] && [ -d "$BOOT_MNT" ] || { echo "ERRO: partição BOOT não encontrada montada. Passe o ponto de montagem manualmente."; exit 1; }

echo "=== Destino: $BOOT_MNT ==="
echo "=== Deploy da tag: $TAG ==="

# --- Sanidade dos ARQUIVOS DE ORIGEM -------------------------------------
# Em 2026-07-21 um teste do script com arquivos criados por `touch` (0 byte)
# sobrescreveu o boot real do HD, que estava montado. Nada no script barrou
# isso: ele copia o que mandarem, inclusive nada. Um bzImage de 0 byte não
# tem como ser válido — melhor recusar do que deixar o HD invalidado.
MIN_BZIMAGE=$((4 * 1024 * 1024))     # builds reais ficam em ~14-16 MB
MIN_INITRAMFS=$((1 * 1024 * 1024))   # ~9 MB nas tags atuais
MIN_BOOTARGS=32                      # a linha de bootargs tem ~380-420 bytes

check_source() {
  local f="$1" min="$2" nome="$3" sz
  sz=$(stat -c%s "$f")
  if [ "$sz" -lt "$min" ]; then
    echo "ERRO: $nome tem $sz bytes (mínimo plausível: $min)."
    echo "      Arquivo: $f"
    echo "      Isso não é um artefato de build válido — deploy abortado para"
    echo "      não invalidar o boot do HD."
    exit 1
  fi
  printf '  OK   %-18s %s bytes\n' "$nome" "$sz"
}
echo "--- Sanidade da origem ---"
check_source "$BZIMAGE"   "$MIN_BZIMAGE"   "bzImage"
check_source "$INITRAMFS" "$MIN_INITRAMFS" "initramfs.cpio.gz"
check_source "$BOOTARGS"  "$MIN_BOOTARGS"  "bootargs.txt"

# --- Espaço livre no destino ---------------------------------------------
# A partição BOOT é pequena (~197 MB) e acumula bzImages antigos. Quando lota,
# o `cp` do backup trunca silenciosamente (foi o que gerou um backup de 462 KB
# no lugar de 15.8 MB). Conferir antes é mais barato que descobrir depois.
NEED=$(( $(stat -c%s "$BZIMAGE") + $(stat -c%s "$INITRAMFS") + $(stat -c%s "$BOOTARGS") ))
AVAIL=$(( $(df -k --output=avail "$BOOT_MNT" | tail -1) * 1024 ))
# o espaço dos arquivos ativos atuais será liberado ao sobrescrevê-los, e os
# bzImages antigos serão removidos logo abaixo — contar ambos como disponíveis
for f in bzImage initramfs.cpio.gz bootargs.txt; do
  [ -f "$BOOT_MNT/$f" ] && AVAIL=$(( AVAIL + $(stat -c%s "$BOOT_MNT/$f") ))
done
for f in "$BOOT_MNT"/bzImage-7.0-*; do
  [ -f "$f" ] && AVAIL=$(( AVAIL + $(stat -c%s "$f") ))
done
if [ "$NEED" -gt "$AVAIL" ]; then
  echo
  echo "ERRO: espaço insuficiente em $BOOT_MNT."
  echo "      Necessário ~$(( NEED / 1024 / 1024 )) MB, disponível ~$(( AVAIL / 1024 / 1024 )) MB."
  echo "      Libere espaço manualmente (o conteúdo grande do HD é descartável:"
  echo "      tudo está versionado em boot_referencia/)."
  exit 1
fi

# --- Regra: no HD fica APENAS o bzImage ativo ----------------------------
# A partição BOOT tem só ~197 MB e cada kernel pesa ~16 MB; guardar histórico
# ali enche a partição e faz o `cp` truncar silenciosamente (aconteceu em
# 2026-07-21). Não há motivo para manter histórico no HD: boot_referencia/ é a
# fonte de verdade e guarda todas as tags. Manter o deploy idempotente —
# rodá-lo duas vezes deixa o HD no mesmo estado.
shopt -s nullglob
OLD_KERNELS=( "$BOOT_MNT"/bzImage-7.0-* )
shopt -u nullglob
if [ ${#OLD_KERNELS[@]} -gt 0 ]; then
  echo "--- Removendo ${#OLD_KERNELS[@]} bzImage(s) antigo(s) do HD (preservados em boot_referencia/) ---"
  rm -f "${OLD_KERNELS[@]}"
fi

# Preservar o que estava ativo antes, com o nome da tag anterior (se houver)
if [ -f "$BOOT_MNT/active-tag.txt" ]; then
  PREV_TAG="$(cat "$BOOT_MNT/active-tag.txt")"
  echo "Ativa anteriormente: $PREV_TAG"
  # O bzImage anterior NÃO é copiado para o HD: ele já está em boot_referencia/
  # sob o nome da tag, e guardar cópia aqui só enche a partição (~16 MB cada).
  # O bootargs, com ~400 bytes, vale manter como histórico local.
  # O `|| true` original mascarava falha de cópia; agora falha alto.
  if [ -f "$BOOT_MNT/bootargs.txt" ]; then
    if ! cp "$BOOT_MNT/bootargs.txt" "$BOOT_MNT/bootargs-7.0-$PREV_TAG.txt"; then
      echo "ERRO: falha ao salvar bootargs-7.0-$PREV_TAG.txt"; exit 1
    fi
  fi
fi

cp "$BZIMAGE"   "$BOOT_MNT/bzImage"
cp "$BOOTARGS"  "$BOOT_MNT/bootargs.txt"
cp "$INITRAMFS" "$BOOT_MNT/initramfs.cpio.gz"
[ -f "$BOOT_MNT/vram.txt" ] || echo "1024" > "$BOOT_MNT/vram.txt"
: > "$BOOT_MNT/bootlog.txt"
echo "$TAG" > "$BOOT_MNT/active-tag.txt"

sync

# Conferência de integridade origem -> destino. A documentação manda validar por
# MD5 antes de cada teste ao vivo; fazer isso aqui elimina o passo manual (e o
# risco de testar um binário diferente do que se pensa estar testando).
echo
echo "=== Conferência MD5 (origem -> destino) ==="
FAIL=0
check_md5() {
  local src="$1" dst="$2" nome="$3"
  local a b
  a="$(md5sum "$src" | cut -d' ' -f1)"
  b="$(md5sum "$dst" | cut -d' ' -f1)"
  if [ "$a" = "$b" ]; then
    printf '  OK   %-18s %s\n' "$nome" "$a"
  else
    printf '  FALHA %-17s origem=%s destino=%s\n' "$nome" "$a" "$b"
    FAIL=1
  fi
}
check_md5 "$BZIMAGE"   "$BOOT_MNT/bzImage"           "bzImage"
check_md5 "$BOOTARGS"  "$BOOT_MNT/bootargs.txt"      "bootargs.txt"
check_md5 "$INITRAMFS" "$BOOT_MNT/initramfs.cpio.gz" "initramfs.cpio.gz"

if [ "$FAIL" -ne 0 ]; then
  echo
  echo "ERRO: algum arquivo não bateu. NÃO teste no console antes de resolver."
  exit 1
fi

echo
echo "=== Deploy concluído: $TAG está ativo em $BOOT_MNT ==="
echo "rootfs (psxitarch) não foi tocado."

# Desmontar as DUAS partições do HD (BOOT/sda1 e psxitarch/sda2).
# Tirar o HD com partição montada deixa o filesystem sujo (dirty bit) e o
# próximo acesso exige fsck — aconteceu em 2026-07-21 com a partição BOOT
# (vfat), que veio com "Dirty bit is set. Fs was not properly unmounted".
# Desmontar aqui, logo após o sync, elimina a janela em que isso acontece.
echo
echo "=== Desmontando partições do HD ==="
UMOUNT_FAIL=0
umount_part() {
  local mnt="$1" nome="$2" src
  [ -n "$mnt" ] || return 0
  if ! mountpoint -q "$mnt" 2>/dev/null; then
    printf '  --   %-12s não estava montado\n' "$nome"
    return 0
  fi
  src="$(findmnt -no SOURCE "$mnt" 2>/dev/null || echo '?')"
  if umount "$mnt" 2>/dev/null \
     || udisksctl unmount -b "$src" >/dev/null 2>&1; then
    printf '  OK   %-12s desmontado (%s)\n' "$nome" "$src"
  else
    printf '  FALHA %-11s ainda montado em %s (%s)\n' "$nome" "$mnt" "$src"
    UMOUNT_FAIL=1
  fi
}

# Só desmontar partições do MESMO disco em que o deploy foi feito. Buscar a
# psxitarch globalmente desmontava o HD real mesmo quando o destino era um
# diretório de teste — bug observado em 2026-07-21.
BOOT_SRC="$(findmnt -no SOURCE "$BOOT_MNT" 2>/dev/null || true)"
if [ -z "$BOOT_SRC" ] || [ ! -b "$BOOT_SRC" ]; then
  echo "  --   destino não é uma partição de bloco ($BOOT_MNT) — nada a desmontar."
else
  DISK="$(lsblk -no PKNAME "$BOOT_SRC" 2>/dev/null | head -1)"
  # desmonta todas as partições montadas do mesmo disco físico
  while read -r mnt lbl src; do
    [ -n "$mnt" ] || continue
    [ "$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)" = "$DISK" ] || continue
    [ "$mnt" = "$BOOT_MNT" ] && continue   # a BOOT vai por último
    umount_part "$mnt" "${lbl:-$src}"
  done < <(lsblk -no MOUNTPOINT,LABEL,PATH | awk 'NF>=2 && $1 ~ /^\//')
  umount_part "$BOOT_MNT" "BOOT"
fi

if [ "$UMOUNT_FAIL" -ne 0 ]; then
  echo
  echo "AVISO: alguma partição não desmontou (processo usando o diretório?)."
  echo "       Resolva antes de tirar o HD — senão o filesystem fica sujo e o"
  echo "       próximo boot/acesso vai exigir fsck."
  echo "       Ver o que está segurando:  sudo lsof +f -- <ponto_de_montagem>"
  exit 1
fi

echo
echo "HD pronto para ser removido com segurança."
