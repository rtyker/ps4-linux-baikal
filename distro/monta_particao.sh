#!/bin/bash
# ==============================================================================
# Montagem de Partições do HD Interno do PS4 (Read-Only & Idempotente)
# Projeto: PS4 Linux Baikal (Kernel 7.0)
#
# Script ÚNICO de produção (MOUNT-02 do BACKLOG_MOUNT.md).
#
# ------------------------------------------------------------------------------
# ESQUEMA DE CRIPTOGRAFIA (validado ao vivo em 2026-11-13)
# ------------------------------------------------------------------------------
# As partições do PS4 são dm-crypt "plain" com AES-XTS-plain64, chave EAP de
# 32 bytes (eap_hdd_key.bin) e — em CUH-1100 e posteriores (todo Baikal) — um
# IV OFFSET não-zero:
#
#       iv_offset = (dev_no - 1) << 32        (fórmula do psdevwiki)
#
#     sda25 (update)   -> 24 << 32 = 103079215104   vfat
#     sda27 (user)     -> 26 << 32 = 111669149696   UFS2
#     sda29 (eap_user) -> 28 << 32 = 120259084288   UFS2
#
# PONTO CRÍTICO: `cryptsetup` NÃO permite definir o iv_offset. As opções
# --offset/--skip são o *data offset* (posição do início dos dados no device),
# não o offset somado ao número do setor na construção do IV. Por isso este
# script cria a tabela do dm-crypt diretamente com `dmsetup`:
#
#   0 <setores> crypt aes-xts-plain64 <chave_hex> <iv_offset> <dev> 0
#
# Abrir com iv_offset=0 (o que o script antigo fazia) produz dados aleatórios:
# o magic UFS2 (0x19540119 em 0x1055C) não aparece e o mount falha.
#
# ------------------------------------------------------------------------------
# PARTIÇÕES
# ------------------------------------------------------------------------------
#   sda13 -> NÃO montável. Não é UFS2; a tabela de partições a mapeia como o
#            swap antigo (swapfs, chave versioned_key + OpenPsId), fora do
#            escopo da chave EAP. Com o iv_offset correto o conteúdo continua
#            aleatório. A psdevwiki também diz "cannot be mounted for now".
#   sda25 -> update  (vfat/FAT32)  — monta
#   sda27 -> user    (UFS2)        — monta (jogos, saves, dados do usuário)
#   sda29 -> eap_user(UFS2)        — monta (storage_stats)
#
# As partições system/system_ex (sda9-sda12), system_data (sda19) e
# app_reserved (sda31) usam a chave SAMU/versioned, NÃO a EAP — não montam aqui.
#
# ------------------------------------------------------------------------------
# Uso
# ------------------------------------------------------------------------------
#   sudo ./monta_particao.sh /dev/sda27
#   sudo ./monta_particao.sh sdb27            # HD interno como sdb (USB = sda)
#   sudo PS4_MOUNT_IV_OFFSET=0 ./monta_particao.sh /dev/sda27   # diagnóstico
#
# Variáveis:
#   PS4_KEYS_DIR        (padrão: /etc/ps4-keys) — pasta canônica da chave EAP
#   PS4_KEYS_FILE       (força um arquivo de chave específico)
#   PS4_MOUNT_IV_OFFSET (padrão: (dev_no-1)<<32; só para diagnóstico)
#   PS4_MOUNT_OPTS      (padrão: ro,noatime,noexec)
#
# ------------------------------------------------------------------------------
# CHAVE EAP (usuário final)
# ------------------------------------------------------------------------------
# A chave dumpada pelo EAPDumper (32 bytes) deve ser colocada em:
#
#     /etc/ps4-keys/eap_hdd_key.bin      (dono root, modo 600)
#
# Ordem de busca (a primeira que existir vence):
#   1. $PS4_KEYS_FILE (override explícito)
#   2. /etc/ps4-keys/eap_hdd_key.bin
#   3. /etc/ps4-keys/ps4_keys.bin
#   4. /etc/ps4-keys/eap_hdd_key.hex   (64 caracteres hex, um por linha ou solto)
#   5. /etc/ps4-keys/eap_hdd_key.txt   (idem; saída .txt do payload)
#   6. /etc/ps4_keys.bin               (compatibilidade com instalações antigas)
#   7. /tmp/keys.bin                   (compatibilidade; /tmp é volátil)
#
# Aceita tanto binário cru de 32 bytes quanto hex de 64 caracteres.
# Use `--check-key` para ver qual arquivo seria usado (sem tocar em nada).
#
# Monta sempre em /mnt/ps4_internal/<part> (NUNCA direto em /mnt).
# ==============================================================================

set -e

MNT_BASE="/mnt/ps4_internal"
KEYS_DIR="${PS4_KEYS_DIR:-/etc/ps4-keys}"
KEY_FILE=""
MOUNT_OPTS="${PS4_MOUNT_OPTS:-ro,noatime,noexec}"

# fusermount não é necessário para nada aqui (UFS2/vfat são FS de kernel), mas
# avisamos o estado porque o MOUNT-06 (PFS games-container via FUSE) depende dele.
FUSERMOUNT_BIN="$(command -v fusermount 2>/dev/null || true)"

# Locais onde procuramos a chave, na ordem.
key_candidates() {
    if [ -n "${PS4_KEYS_FILE:-}" ]; then
        echo "$PS4_KEYS_FILE"
    fi
    echo "$KEYS_DIR/eap_hdd_key.bin"
    echo "$KEYS_DIR/ps4_keys.bin"
    echo "$KEYS_DIR/eap_hdd_key.hex"
    echo "$KEYS_DIR/eap_hdd_key.txt"
    echo "/etc/ps4_keys.bin"
    echo "/tmp/keys.bin"
}

resolve_key_file() {
    local f
    while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }
    done < <(key_candidates)
    return 1
}

# Converte o conteúdo do arquivo em 64 caracteres hex (formato da tabela dm-crypt).
key_hex_from_file() {
    local f="$1" size hex
    size=$(stat -c %s "$f" 2>/dev/null || echo 0)
    if [ "$size" -eq 32 ]; then
        xxd -p -c 256 "$f" | tr -d '\n'
        return 0
    fi
    # 33 bytes = 32 binários + newline (ex.: `cat chave.bin; echo`).
    if [ "$size" -eq 33 ] && [ "$(tail -c 1 "$f" | xxd -p)" = "0a" ]; then
        head -c 32 "$f" | xxd -p -c 256 | tr -d '\n'
        return 0
    fi
    # Arquivo texto: prefere um token isolado de exatamente 64 hex; senão, o
    # primeiro trecho de 64 hex encontrado (ex.: saída .txt do EAPDumper).
    hex=$(awk '{for (i=1;i<=NF;i++) if ($i ~ /^[0-9a-fA-F]{64}$/) {print $i; exit}}' "$f" 2>/dev/null)
    if [ -z "$hex" ]; then
        hex=$(grep -oE '[0-9a-fA-F]{64}' "$f" 2>/dev/null | head -1)
    fi
    printf '%s' "$hex"
}

key_help() {
    echo "Coloque a chave EAP (dump do EAPDumper, 32 bytes) em:"
    echo "    $KEYS_DIR/eap_hdd_key.bin"
    echo "  com dono root e modo 600:"
    echo "    sudo install -d -m 700 -o root -g root $KEYS_DIR"
    echo "    sudo install -m 600 -o root -g root <arquivo-dumpado> $KEYS_DIR/eap_hdd_key.bin"
    echo "Ou, no PC, use: distro/scripts/provisiona-chave.sh <arquivo> --ssh root@<ip-do-ps4>"
    echo "Locais procurados:"
    key_candidates | sed 's/^/    /'
}

usage() {
    cat <<'EOF'
Uso: monta_particao.sh <partição> | --check-key | --help

  monta_particao.sh /dev/sda27     # UFS2 (user)   — jogos, saves, dados
  monta_particao.sh /dev/sda29     # UFS2 (eap_user)
  monta_particao.sh /dev/sda25     # FAT32 (update)
  monta_particao.sh sdb27          # HD interno como sdb (USB de boot = sda)
  monta_particao.sh 27             # atalho (usa PS4_INTERNAL_DEV, padrão sda)
  monta_particao.sh --check-key    # mostra qual arquivo de chave seria usado

sda13 não é montável (swap antigo / chave versioned_key, não EAP).

Chave EAP: /etc/ps4-keys/eap_hdd_key.bin (dono root, modo 600).
Aceita binário de 32 bytes ou hex de 64 caracteres.

Variáveis:
  PS4_KEYS_DIR        (padrão: /etc/ps4-keys)
  PS4_KEYS_FILE       (força um arquivo específico)
  PS4_MOUNT_IV_OFFSET (padrão: (dev_no-1)<<32; apenas para diagnóstico)
  PS4_MOUNT_OPTS      (padrão: ro,noatime,noexec)

Monta sempre em /mnt/ps4_internal/<part> (nunca direto em /mnt).
EOF
    exit "${1:-1}"
}

# -h/--help: ajuda com exit 0.
case "${1:-}" in
    -h|--help) usage 0 ;;
esac

# --check-key: valida a presença/formato da chave sem tocar no HD.
# Usado pelo automount.sh (e testável fora do PS4).
if [ "${1:-}" = "--check-key" ]; then
    if ! KEY_FILE="$(resolve_key_file)"; then
        echo "Nenhuma chave EAP encontrada." >&2
        key_help >&2
        exit 1
    fi
    KEY_HEX="$(key_hex_from_file "$KEY_FILE")"
    if [ "${#KEY_HEX}" -ne 64 ]; then
        echo "Arquivo de chave inválido: $KEY_FILE (${#KEY_HEX} caracteres hex; esperado 64)." >&2
        echo "Esperado: 32 bytes binários ou 64 caracteres hex." >&2
        exit 1
    fi
    PERM="$(stat -c %a "$KEY_FILE" 2>/dev/null || echo '?')"
    case "$PERM" in
        600|400) ;;
        *) echo "Aviso: $KEY_FILE tem modo $PERM (recomendado 600)." >&2 ;;
    esac
    echo "chave: $KEY_FILE"
    exit 0
fi

[ -n "${1:-}" ] || usage

# Aceita /dev/sda27, sda27 ou 27
case "$1" in
    /dev/*) PART_DEV="$1" ;;
    [0-9]*) PART_DEV="/dev/${PS4_INTERNAL_DEV:-sda}$1" ;;
    *)      PART_DEV="/dev/$1" ;;
esac

PART_NAME="$(basename "$PART_DEV")"
DEVNO="$(echo "$PART_NAME" | sed -n 's/^[a-z]*\([0-9][0-9]*\)$/\1/p')"
if [ -z "$DEVNO" ]; then
    echo "Erro: não consegui extrair o número da partição de '$PART_NAME'."
    exit 1
fi

MNT_DIR="$MNT_BASE/$PART_NAME"
MAPPER_NAME="ps4_$PART_NAME"
IV_OFFSET="${PS4_MOUNT_IV_OFFSET:-$(( (DEVNO - 1) << 32 ))}"

if [ ! -b "$PART_DEV" ]; then
    echo "Erro: dispositivo $PART_DEV não encontrado."
    exit 1
fi

mkdir -p "$MNT_DIR"

# ------------------------------------------------------------------------------
# 1. Idempotência: já montado?
# ------------------------------------------------------------------------------
if mountpoint -q "$MNT_DIR" 2>/dev/null; then
    echo "Info: $MNT_DIR já está montado. Nada a fazer."
    exit 0
fi

# ------------------------------------------------------------------------------
# 2. Chave EAP: localiza o arquivo e converte para hex
# ------------------------------------------------------------------------------
if ! KEY_FILE="$(resolve_key_file)"; then
    echo "Erro: nenhuma chave EAP encontrada." >&2
    key_help >&2
    exit 1
fi

KEY_HEX="$(key_hex_from_file "$KEY_FILE")"
if [ "${#KEY_HEX}" -ne 64 ]; then
    echo "Erro: chave inválida em $KEY_FILE (${#KEY_HEX} caracteres hex; esperado 64)." >&2
    echo "      Esperado: 32 bytes binários ou 64 caracteres hex." >&2
    key_help >&2
    exit 1
fi

SECTORS="$(blockdev --getsz "$PART_DEV")"

# ------------------------------------------------------------------------------
# 3. Mapper: cria (ou recria, se o iv_offset estiver errado)
# ------------------------------------------------------------------------------
echo "=== Mapeando $PART_DEV (AES-XTS-plain64, iv_offset=$IV_OFFSET) ==="

if [ -e "/dev/mapper/$MAPPER_NAME" ]; then
    CUR_IV="$(dmsetup table "$MAPPER_NAME" 2>/dev/null | awk '{print $6}')"
    if [ "$CUR_IV" = "$IV_OFFSET" ]; then
        echo "Mapper /dev/mapper/$MAPPER_NAME já existe com iv_offset correto, reutilizando."
    else
        echo "Mapper existente tem iv_offset='$CUR_IV' (esperado '$IV_OFFSET') — recriando."
        umount "$MNT_DIR" 2>/dev/null || true
        dmsetup remove "$MAPPER_NAME" 2>/dev/null || cryptsetup remove "$MAPPER_NAME"
    fi
fi

if [ ! -e "/dev/mapper/$MAPPER_NAME" ]; then
    if ! dmsetup create -r "$MAPPER_NAME" --table \
        "0 $SECTORS crypt aes-xts-plain64 $KEY_HEX $IV_OFFSET $PART_DEV 0"; then
        echo "Erro: falha ao criar o mapper $MAPPER_NAME (dmsetup)."
        exit 1
    fi
    echo "Mapper criado: /dev/mapper/$MAPPER_NAME (readonly)"
fi

# ------------------------------------------------------------------------------
# 4. Montagem do filesystem (detectado por blkid)
# ------------------------------------------------------------------------------
echo "=== Montando /dev/mapper/$MAPPER_NAME em $MNT_DIR ($MOUNT_OPTS) ==="

FS_TYPE="$(blkid -p -s TYPE -o value "/dev/mapper/$MAPPER_NAME" 2>/dev/null || true)"
FS_VER="$(blkid -p -s VERSION -o value "/dev/mapper/$MAPPER_NAME" 2>/dev/null || true)"

echo "Filesystem detectado: ${FS_TYPE:-desconhecido}${FS_VER:+ (versão $FS_VER)}"
if [ -n "$FUSERMOUNT_BIN" ]; then
    echo "Info: fusermount disponível ($FUSERMOUNT_BIN) para futuros filesystems FUSE (PFS)."
fi

MOUNT_OK=0
case "$FS_TYPE" in
    ufs)
        if mount -t ufs -o "ufstype=ufs2,$MOUNT_OPTS" "/dev/mapper/$MAPPER_NAME" "$MNT_DIR"; then
            MOUNT_OK=1
        fi
        ;;
    vfat|msdos|fat|exfat)
        if mount -t "$FS_TYPE" -o "$MOUNT_OPTS" "/dev/mapper/$MAPPER_NAME" "$MNT_DIR"; then
            MOUNT_OK=1
        fi
        ;;
    *)
        # Sem tipo detectado: vale a pena tentar UFS2 (magic em offset
        # inesperado) e, por último, deixar o kernel decidir.
        if mount -t ufs -o "ufstype=ufs2,$MOUNT_OPTS" "/dev/mapper/$MAPPER_NAME" "$MNT_DIR" 2>/dev/null; then
            MOUNT_OK=1
        elif mount -o "$MOUNT_OPTS" "/dev/mapper/$MAPPER_NAME" "$MNT_DIR"; then
            MOUNT_OK=1
        fi
        ;;
esac

if [ "$MOUNT_OK" -eq 1 ]; then
    echo "Sucesso: $PART_NAME montado em $MNT_DIR"
    exit 0
fi

# ------------------------------------------------------------------------------
# 5. Falha: diagnóstico
# ------------------------------------------------------------------------------
echo "Aviso: o mapper /dev/mapper/$MAPPER_NAME está ativo (readonly), mas o mount falhou."
if [ -z "$FS_TYPE" ]; then
    echo "Nenhum filesystem reconhecível: o iv_offset provavelmente está errado para"
    echo "esta partição, ou ela usa outra chave (SAMU/versioned_key em vez de EAP)."
else
    echo "Filesystem '$FS_TYPE' detectado mas o mount falhou: veja 'dmesg | tail'."
fi
echo "Diagnóstico:"
echo "  dmsetup table $MAPPER_NAME          # confira o campo iv_offset"
echo "  blkid -p /dev/mapper/$MAPPER_NAME   # tipo/versão detectados"
echo "  dd if=/dev/mapper/$MAPPER_NAME bs=1 skip=66908 count=4 2>/dev/null | xxd"
echo "      (magic UFS2 esperado: 1901 5419)"
echo "Partições system/system_ex/system_data/app_reserved usam a chave SAMU, não a EAP."
exit 1
