#!/usr/bin/env bash
# Gera initramfs com o arquivo NVRAM do WiFi MediaTek (MT6632/MT7668) acrescentado.
# RE/diagnóstico — NÃO é script de build. Não grava nada no PS4.
#
# Uso: gen_wifi_nvram_initramfs.sh <initramfs_original.cpio.gz> <saida.cpio> [MAC] [PAIS]
#   MAC   padrão: E8:D8:19:93:CC:AF (eFUSE 0x004-0x009, a confirmar)
#   PAIS  padrão: BR
#
# Formato: o arquivo da BOOT é cpio newc SEM compressão (magic 070701).
# Acrescentar um segundo archive cpio ao final é desempacotado em sequência pelo kernel.
set -euo pipefail

ORIG="${1:?informe o initramfs original}"
OUT="${2:?informe o arquivo de saída}"
MAC="${3:-E8:D8:19:93:CC:AF}"
PAIS="${4:-BR}"

command -v cpio >/dev/null || { echo "ERRO: cpio não instalado"; exit 1; }
[ "${#PAIS}" -eq 2 ] || { echo "ERRO: país deve ter 2 letras"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/frag/data/nvram/APCFG/APRDEB"

python3 - "$WORK/frag/data/nvram/APCFG/APRDEB/WIFI" "$MAC" "$PAIS" <<'PY'
import struct, sys
path, mac, pais = sys.argv[1], sys.argv[2], sys.argv[3]
buf = bytearray(512)                         # WIFI_CFG_PARAM_STRUCT = 512 bytes
OWN = (2 << 8) | 0                           # CFG_DRV_OWN_VERSION (os/version.h 2.0)
struct.pack_into('<H', buf, 0, OWN)          # u2Part1OwnVersion
struct.pack_into('<H', buf, 2, 0)            # u2Part1PeerVersion
buf[4:10] = bytes(int(x, 16) for x in mac.split(':'))  # aucMacAddress
buf[10:12] = pais.encode('ascii')            # aucCountryCode
struct.pack_into('<H', buf, 256, OWN)        # u2Part2OwnVersion
struct.pack_into('<H', buf, 258, 0)          # u2Part2PeerVersion
open(path, 'wb').write(bytes(buf))
PY

( cd "$WORK/frag" && find . | cpio -o -H newc --quiet ) > "$WORK/frag.cpio"
# Se o original for gzip, descomprime antes; se já for cpio puro, usa direto.
if zcat -t "$ORIG" >/dev/null 2>&1; then
  zcat "$ORIG" > "$WORK/orig.cpio"
else
  cp "$ORIG" "$WORK/orig.cpio"
fi
cat "$WORK/orig.cpio" "$WORK/frag.cpio" > "$OUT"

# Verificação: o segundo archive precisa extrair o WIFI idêntico.
O=$(stat -c%s "$WORK/orig.cpio")
mkdir "$WORK/check"
tail -c +$((O+1)) "$OUT" | ( cd "$WORK/check" && cpio -id --quiet )
cmp "$WORK/check/data/nvram/APCFG/APRDEB/WIFI" "$WORK/frag/data/nvram/APCFG/APRDEB/WIFI"
echo "OK: $OUT  (original=$O bytes, MAC=$MAC, país=$PAIS)"
