#!/usr/bin/env bash
# build_dma_modules.sh <dir_saida> — recompila FORA da árvore do kernel os módulos
# virt-dma, baikal-dmac, dmatest e rtc-ps4-icc, prontos para `insmod` no PS4.
#
# Para iterar versões do driver sem rebuild do kernel. NÃO substitui o build
# oficial (kernel/00-build-kernel-7.0.sh), que continua sendo o único que gera
# bzImage/tag. A fonte do baikal-dmac vem de kernel/patches/baikal-dmac.patch
# (fonte única); as demais, da árvore do kernel.
#
# Uso:   others/rea/dma/harness/build_dma_modules.sh /tmp/dmamods
# Opcional: KERNEL_TREE=/caminho/kernel_build_7.0  (padrão: kernel/kernel_build_7.0)
#
# Contornos (todos descobertos na prática, 2026-11-13):
#  1. Se a árvore perdeu os arquivos gerados (scripts/module.lds), roda
#     `modules_prepare` (~3 s, não recompila o kernel).
#  2. `KBUILD_MODPOST_WARN=1`: sem Module.symvers na árvore o modpost reclama de
#     símbolos do kernel; o kernel do PS4 tem CONFIG_MODVERSIONS desligado, então
#     os símbolos são resolvidos no insmod e isso é seguro.
#  3. `CONFIG_DEBUG_INFO_BTF_MODULES=` (vazio): sem vmlinux na árvore a regra do
#     .ko exigiria o vmlinux para gerar BTF. Removemos o BTF de qualquer forma:
#     módulo com BTF de outro build falha no PS4 com "failed to validate module
#     BTF: -22" (foi o que derrubou o rtc-ps4-icc do rootfs).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
KT="${KERNEL_TREE:-$ROOT/kernel/kernel_build_7.0}"
PATCH="$ROOT/kernel/patches/baikal-dmac.patch"
OUT="${1:?uso: $0 <dir_saida>}"

[ -f "$KT/.config" ] || { echo "ERRO: $KT/.config não existe (árvore do kernel ausente?)"; exit 1; }
[ -f "$PATCH" ]      || { echo "ERRO: $PATCH não encontrado"; exit 1; }
command -v clang >/dev/null && command -v ld.lld >/dev/null || { echo "ERRO: clang/ld.lld ausentes"; exit 1; }

if [ ! -f "$KT/scripts/module.lds" ]; then
  echo "== modules_prepare (árvore sem arquivos gerados) =="
  sudo make -C "$KT" -j4 LLVM=1 ARCH=x86_64 modules_prepare >/dev/null
fi

SRC="$OUT/src"
rm -rf "$SRC"; mkdir -p "$SRC" "$OUT/x"

# baikal-dmac.c: extraído do patch (fonte única), nunca copiado da árvore.
( cd "$OUT/x" && git apply --include='drivers/dma/baikal-dmac.c' "$PATCH" )
cp "$OUT/x/drivers/dma/baikal-dmac.c" "$SRC/"
cp "$KT/drivers/dma/"{virt-dma.c,virt-dma.h,dmaengine.h,dmatest.c} "$SRC/"
cp "$KT/drivers/rtc/rtc-ps4-icc.c" "$SRC/"
echo 'obj-m += virt-dma.o baikal-dmac.o dmatest.o rtc-ps4-icc.o' > "$SRC/Makefile"

echo "== compilando =="
sudo make -C "$KT" M="$SRC" ARCH=x86_64 LLVM=1 CC=clang \
     KBUILD_MODPOST_WARN=1 CONFIG_DEBUG_INFO_BTF_MODULES= modules 2>&1 \
  | grep -E "error:|Error |LD \[M\]" || true
sudo chown -R "$(id -un):$(id -gn)" "$SRC"

for m in virt-dma baikal-dmac dmatest rtc-ps4-icc; do
  [ -f "$SRC/$m.ko" ] || { echo "ERRO: $m.ko não foi gerado"; exit 1; }
  objcopy --remove-section=.BTF --remove-section=.BTF.base "$SRC/$m.ko" 2>/dev/null || true
  cp "$SRC/$m.ko" "$OUT/"
  printf '  %-13s %s | %s\n' "$m.ko" "$(strings "$OUT/$m.ko" | grep -m1 '^vermagic=' | cut -c1-58)" \
         "$(strings "$OUT/$m.ko" | grep -m1 '^depends=')"
done
echo "== prontos em $OUT =="
echo "No PS4:  insmod virt-dma.ko && insmod baikal-dmac.ko   (e dmatest.ko para validar)"
