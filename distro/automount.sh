#!/bin/bash
# ==============================================================================
# Script de Montagem Automática do HD Interno do PS4 (sda13 & sda27)
# Projeto: PS4 Linux Baikal (Kernel 7.0)
# ==============================================================================

set -e

MONTA_CMD="/usr/local/bin/monta_particao.sh"

if [ ! -x "$MONTA_CMD" ]; then
    if [ -x "$(dirname "$0")/monta_particao.sh" ]; then
        MONTA_CMD="$(dirname "$0")/monta_particao.sh"
    else
        echo "Erro: Utilitário monta_particao.sh não foi encontrado ou não tem permissão de execução!"
        exit 1
    fi
fi

echo "========================================================"
echo "⚡ Montando Partições Principais do HD Interno do PS4 ⚡"
echo "========================================================"

# Descobre o device do HD INTERNO sem assumir /dev/sda:
# com o HD USB plugged, o USB costuma ser sda (BOOT=sda1, rootfs=sda2) e o
# interno é sdb. Nos testes antigos o interno era sda (USB em sdb) — por isso
# testamos os dois, em ordem, e toleramos a ausência.
INTERNAL_DEV=""
for cand in sdb sda; do
  if [ -b "/dev/${cand}13" ] || [ -b "/dev/${cand}27" ]; then
    INTERNAL_DEV="$cand"
    break
  fi
done

if [ -z "$INTERNAL_DEV" ]; then
  echo "Aviso: HD interno não encontrado (procurado /dev/sdb13, /dev/sda13)."
  echo "       Nada a montar — o serviço termina sem erro."
  exit 0
fi

echo "HD interno detectado em /dev/$INTERNAL_DEV"

for part in 13 27; do
  dev="/dev/${INTERNAL_DEV}${part}"
  if [ ! -b "$dev" ]; then
    echo "Aviso: $dev não existe — partição pulada."
    continue
  fi
  case "$part" in
    13) echo "--> Partição de Sistema Orbis ($dev)" ;;
    27) echo "--> Partição de Dados e Jogos ($dev)" ;;
  esac
  "$MONTA_CMD" "$dev" || echo "Aviso: falha ao montar $dev (continuando)."
done

echo ""
echo "========================================================"
echo "✅ Montagem Automática Concluída com Sucesso!"
echo "========================================================"
echo "Mappers ativos:"
ls -lh /dev/mapper/ps4_* 2>/dev/null || true
