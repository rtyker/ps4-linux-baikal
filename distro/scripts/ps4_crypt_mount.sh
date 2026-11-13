#!/bin/bash
# ==============================================================================
# ⚠️  LEGADO — NÃO USE. Mantido apenas como shim para não quebrar links/scripts
#     antigos. O script de produção é `distro/monta_particao.sh`.
#
#     Histórico: esta era a primeira tentativa (via `cryptsetup ... --offset
#     <LBA>`), baseada na hipótese de que o tweak/IV era o LBA absoluto da
#     partição. A hipótese foi REFUTADA ao vivo em 2026-11-13: o offset correto
#     é o IV offset `(dev_no - 1) << 32`, que o `cryptsetup` não sabe aplicar —
#     por isso o `monta_particao.sh` usa `dmsetup`. Ver MONTAGEM_HD_INTERNO.md §2.
#
#     Não é copiado para o rootfs pelo 01-build-image-7.0.sh.
# ==============================================================================

set -u

echo "Aviso: ps4_crypt_mount.sh é LEGADO (esquema de IV refutado)."
echo "        Delegando para o script de produção monta_particao.sh..."
echo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONTA="$SCRIPT_DIR/../monta_particao.sh"

if [ ! -x "$MONTA" ]; then
    echo "Erro: $MONTA não encontrado/executável."
    exit 1
fi

if [ $# -lt 1 ]; then
    echo "Uso: $0 /dev/sdaX [ponto_de_montagem_ignorado]"
    exit 1
fi

exec "$MONTA" "$1"
