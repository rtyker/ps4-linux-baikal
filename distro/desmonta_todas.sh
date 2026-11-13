#!/bin/bash
# ==============================================================================
# Desmonta TODAS as partições do HD interno do PS4 e remove os mappers ps4_*
# Projeto: PS4 Linux Baikal (Kernel 7.0)
#
# Usado como ExecStop do ps4-automount.service (MOUNT-07 do BACKLOG_MOUNT.md).
# Antes o ExecStop era `desmonta_particao.sh /dev/sda27` — desmontava só uma
# partição e com caminho fixo /dev/sda27, falhando quando o HD interno era
# /dev/sdb (caso comum com o HD USB de boot plugado como sda).
#
# Idempotente: não falha se nada estiver montado/mapeado.
# ==============================================================================

set -u

MNT_BASE="/mnt/ps4_internal"

echo "=== Desmontando partições em $MNT_BASE ==="
if [ -d "$MNT_BASE" ]; then
    for mnt in "$MNT_BASE"/*; do
        [ -e "$mnt" ] || continue
        if mountpoint -q "$mnt" 2>/dev/null; then
            if umount "$mnt" 2>/dev/null; then
                echo "Desmontado: $mnt"
            else
                echo "Aviso: falha ao desmontar $mnt (processo usando o diretório?)"
            fi
        fi
    done
fi

echo "=== Removendo mappers ps4_* ==="
for mapper in /dev/mapper/ps4_*; do
    [ -e "$mapper" ] || continue
    name=$(basename "$mapper")
    if dmsetup remove "$name" 2>/dev/null || cryptsetup remove "$name" 2>/dev/null; then
        echo "Mapper removido: $name"
    else
        echo "Aviso: falha ao remover $name"
    fi
done

echo "Concluído: desmontagem de todas as partições do HD interno."
