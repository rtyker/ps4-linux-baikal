#!/bin/bash
# ==============================================================================
# Montagem automática das partições do HD interno do PS4
# Projeto: PS4 Linux Baikal (Kernel 7.0)
#
# Monta, em modo read-only, as partições acessíveis com a chave EAP:
#   sda27 -> user     (UFS2)  — jogos, saves e dados do usuário
#   sda29 -> eap_user (UFS2)  — storage_stats
#   sda25 -> update   (FAT32) — conteúdo de atualização (PS4UPDATE.PUP)
#
# NÃO monta:
#   sda13 -> swap antigo (swapfs, chave versioned_key + OpenPsId): não é UFS2
#            e não é decifrável com a chave EAP (ver BACKLOG_MOUNT.md).
#   sda9-12/sda19/sda31 -> usam a chave SAMU/versioned, não a EAP.
#
# O IV offset correto — iv_offset = (dev_no - 1) << 32 — é aplicado pelo
# monta_particao.sh (dmsetup), validado ao vivo em 2026-11-13.
#
# CHAVE EAP: as partições são dm-crypt/AES-XTS, então sem a chave do usuário não
# há o que montar. A chave fica em /etc/ps4-keys/eap_hdd_key.bin (root, 600) e é
# provisionada com distro/scripts/provisiona-chave.sh. Chave ausente NÃO é erro:
# o script avisa uma vez e sai com 0 (instalação nova do usuário).
# ==============================================================================

set -u

MONTA_CMD="$(dirname "$0")/monta_particao.sh"

if [ -x /usr/local/bin/monta_particao.sh ]; then
    MONTA_CMD="/usr/local/bin/monta_particao.sh"
fi

if [ ! -x "$MONTA_CMD" ]; then
    echo "Erro: monta_particao.sh não encontrado ou sem permissão de execução."
    exit 1
fi

echo "========================================================="
echo "⚡ Montando Partições do HD Interno do PS4 (read-only) ⚡"
echo "========================================================="

# Descobre o device do HD interno sem assumir /dev/sda: com o HD USB de boot
# plugado, o USB costuma ser sda e o interno sdb (e vice-versa em outros setups).
INTERNAL_DEV=""
for cand in sdb sda; do
    if [ -b "/dev/${cand}27" ]; then
        INTERNAL_DEV="$cand"
        break
    fi
done

if [ -z "$INTERNAL_DEV" ]; then
    echo "Aviso: HD interno não encontrado (procurado /dev/sdb27, /dev/sda27)."
    echo "       Nada a montar — terminando sem erro."
    exit 0
fi

# ------------------------------------------------------------------------------
# Chave EAP: sem ela as partições são ciphertext (AES-XTS conforme a partição).
# Sem chave NÃO é erro — só não há o que montar (instalação nova do usuário).
# ------------------------------------------------------------------------------
if ! "$MONTA_CMD" --check-key >/dev/null 2>&1; then
    echo ""
    echo "========================================================="
    echo "ℹ️  Chave EAP do HD interno não encontrada — nada montado."
    echo "========================================================="
    echo "Coloque a chave dumpada pelo EAPDumper (32 bytes) em:"
    echo ""
    echo "    /etc/ps4-keys/eap_hdd_key.bin     (dono root, modo 600)"
    echo ""
    echo "Ou, a partir deste PC (com SSH no PS4 ligado):"
    echo "    distro/scripts/provisiona-chave.sh <arquivo> --ssh root@<ip-do-ps4>"
    echo ""
    echo "Depois recarregue o serviço:"
    echo "    systemctl restart ps4-automount.service"
    echo "Detalhes: others/docs/MONTAGEM_HD_INTERNO.md"
    exit 0
fi

echo "HD interno detectado em /dev/$INTERNAL_DEV"
export PS4_INTERNAL_DEV="$INTERNAL_DEV"

FAILED=0
for part in 27 29 25; do
    dev="/dev/${INTERNAL_DEV}${part}"
    case "$part" in
        27) label="user (UFS2)" ;;
        29) label="eap_user (UFS2)" ;;
        25) label="update (FAT32)" ;;
    esac

    if [ ! -b "$dev" ]; then
        echo "Aviso: $dev não existe — partição pulada."
        continue
    fi

    echo ""
    echo "--> $label em $dev"
    if ! "$MONTA_CMD" "$dev"; then
        echo "Aviso: falha ao montar $dev (continuando)."
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "========================================================="
if [ "$FAILED" -eq 0 ]; then
    echo "✅ Montagem automática concluída."
else
    echo "⚠️  Montagem concluída com $FAILED falha(s) — veja acima."
fi
echo "========================================================="
echo "Partições montadas em /mnt/ps4_internal:"
ls -1 /mnt/ps4_internal 2>/dev/null || true
echo "Mappers ativos:"
ls -1 /dev/mapper/ps4_* 2>/dev/null || true

exit 0
