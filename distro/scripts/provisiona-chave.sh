#!/bin/bash
# ==============================================================================
# Provisiona a chave EAP do HD interno do PS4 no rootfs do Linux (Baikal)
# Projeto: PS4 Linux Baikal (Kernel 7.0)
#
# O QUE FAZ
#   Pega o arquivo dumpado pelo EAPDumper (32 bytes crus, hex de 64 caracteres
#   ou a saída .txt do payload), normaliza, valida e instala como:
#
#       /etc/ps4-keys/eap_hdd_key.bin      (dono root, modo 600)
#
#   A partir daí o `automount.sh` (serviço ps4-automount.service) monta sozinho
#   as partições sda27 (user/UFS2), sda29 (eap_user/UFS2) e sda25 (update/FAT32)
#   em /mnt/ps4_internal/... a cada boot — sem tocar no sda13 (swap antigo).
#
# MODOS
#   --ssh root@IP     instala no PS4 ligado, via SSH (padrão: root@192.168.6.128)
#   --rootfs DIR      instala direto num rootfs montado neste PC
#                     (ex.: /mnt/ps4_rootfs_7.0)
#
# SEGURANÇA
#   A chave é o segredo que decifra o HD inteiro. Nunca comite, nunca deixe
#   modo 644, nunca cole em issue/chat. Este script escreve modo 600 e não
#   imprime a chave (só o sha256, para conferência).
#
# EXEMPLOS
#   distro/scripts/provisiona-chave.sh ~/keys.bin
#   distro/scripts/provisiona-chave.sh ~/eap_dump.txt --ssh root@192.168.6.128
#   PS4_SSH_PASS=ps4 distro/scripts/provisiona-chave.sh ~/keys.bin --no-verify
#   sudo distro/scripts/provisiona-chave.sh ~/keys.bin --rootfs /mnt/ps4_rootfs_7.0
# ==============================================================================

set -u

DEST_REL="/etc/ps4-keys/eap_hdd_key.bin"
MODE="ssh"
SSH_TARGET="root@192.168.6.128"
ROOTFS_DIR=""
VERIFY=1
SRC=""

usage() {
    cat <<'EOF'
Uso: provisiona-chave.sh <arquivo-da-chave> [opções]

  <arquivo-da-chave>   dump do EAPDumper: 32 bytes binários, 64 caracteres hex
                       ou a saída .txt do payload (o hex é extraído do texto)

Opções:
  --ssh [user@]host    instala no PS4 via SSH (padrão: root@192.168.6.128)
  --rootfs DIR         instala num rootfs montado localmente
  --dest CAMINHO       caminho de destino dentro do rootfs
                       (padrão: /etc/ps4-keys/eap_hdd_key.bin)
  --no-verify          não tenta montar o sda27 para conferir a chave
  -h, --help           esta ajuda

Variáveis:
  PS4_SSH_PASS         senha do SSH (usa sshpass se definida)
  PS4_KEYS_DIR         pasta alternativa da chave (padrão: /etc/ps4-keys)

A chave instalada nunca é exibida — só o sha256, para conferência.
EOF
}

die() { echo "Erro: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --ssh)
            [ $# -ge 2 ] || die "--ssh exige um alvo (ex.: root@192.168.6.128)"
            MODE="ssh"; SSH_TARGET="$2"; shift 2 ;;
        --rootfs)
            [ $# -ge 2 ] || die "--rootfs exige um diretório"
            MODE="rootfs"; ROOTFS_DIR="${2%/}"; shift 2 ;;
        --dest)
            [ $# -ge 2 ] || die "--dest exige um caminho"
            DEST_REL="$2"; shift 2 ;;
        --no-verify) VERIFY=0; shift ;;
        --*) die "opção desconhecida: $1 (use --help)" ;;
        *)
            [ -z "$SRC" ] || die "só um arquivo de chave por vez (recebi '$SRC' e '$1')"
            SRC="$1"; shift ;;
    esac
done

[ -n "$SRC" ] || { usage; exit 1; }
[ -f "$SRC" ] || die "arquivo '$SRC' não existe"

case "$DEST_REL" in
    /*) ;;
    *) DEST_REL="/etc/ps4-keys/$DEST_REL" ;;
esac

# ------------------------------------------------------------------------------
# 1. Normaliza a chave para 32 bytes (hex de 64 caracteres)
# ------------------------------------------------------------------------------
STATE="$(mktemp -d "${TMPDIR:-/tmp}/ps4-chave.XXXXXX")"
trap 'rm -rf "$STATE"' EXIT
chmod 700 "$STATE"

KEY_BIN="$STATE/eap_hdd_key.bin"

extract_hex() {
    local src="$1" size hex=""
    size="$(stat -c %s "$src" 2>/dev/null || echo 0)"
    if [ "$size" -eq 32 ]; then
        # Caminho feliz: dump binário cru de 32 bytes.
        xxd -p -c 256 "$src" | tr -d '\n'
        return 0
    fi
    # 33 bytes = 32 binários + newline (ex.: `cat chave.bin; echo`).
    if [ "$size" -eq 33 ] && [ "$(tail -c 1 "$src" | xxd -p)" = "0a" ]; then
        head -c 32 "$src" | xxd -p -c 256 | tr -d '\n'
        return 0
    fi
    if [ "$size" -eq 64 ]; then
        hex="$(tr -d '[:space:]' < "$src")"
        case "$hex" in
            *[!0-9a-fA-F]*) hex="" ;;
        esac
        if [ -n "$hex" ]; then
            printf '%s' "$hex"
            return 0
        fi
    fi
    # Arquivo texto (saída .txt do EAPDumper, log, etc.): token isolado de
    # exatamente 64 hex tem prioridade sobre "primeiro trecho de 64 hex".
    hex="$(awk '{for (i=1;i<=NF;i++) if ($i ~ /^[0-9a-fA-F]{64}$/) {print $i; exit}}' "$src" 2>/dev/null)"
    if [ -z "$hex" ]; then
        hex="$(tr -d '\r\n' < "$src" | grep -oE '[0-9a-fA-F]{64}' | head -1)"
    fi
    printf '%s' "$hex"
}

KEY_HEX="$(extract_hex "$SRC")"
KEY_HEX="$(printf '%s' "$KEY_HEX" | tr 'A-F' 'a-f')"

[ "${#KEY_HEX}" -eq 64 ] || die "não encontrei uma chave de 32 bytes (64 hex) em '$SRC'
       tamanho do arquivo: $(stat -c %s "$SRC" 2>/dev/null || echo '?') bytes
       esperado: 32 bytes binários, 64 caracteres hex ou um .txt com o hex"

printf '%s' "$KEY_HEX" | xxd -r -p > "$KEY_BIN"
chmod 600 "$KEY_BIN"
[ "$(stat -c %s "$KEY_BIN")" -eq 32 ] || die "falha ao converter a chave (o arquivo final não tem 32 bytes)"

KEY_SHA="$(sha256sum "$KEY_BIN" | awk '{print $1}')"

echo "========================================================="
echo "🔑 Chave EAP normalizada (32 bytes / AES-XTS-256)"
echo "========================================================="
echo "origem : $SRC"
echo "sha256 : $KEY_SHA"
echo "destino: $DEST_REL"
echo ""

# ------------------------------------------------------------------------------
# 2. Instala (SSH no PS4 ou rootfs montado localmente)
# ------------------------------------------------------------------------------
DEST_DIR="$(dirname "$DEST_REL")"

ssh_run() {
    if [ -n "${PS4_SSH_PASS:-}" ]; then
        sshpass -p "$PS4_SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$SSH_TARGET" "$@"
    else
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$SSH_TARGET" "$@"
    fi
}

scp_put() {
    if [ -n "${PS4_SSH_PASS:-}" ]; then
        sshpass -p "$PS4_SSH_PASS" scp -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$1" "$SSH_TARGET:$2"
    else
        scp -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$1" "$SSH_TARGET:$2"
    fi
}

if [ "$MODE" = "ssh" ]; then
    echo "--> Instalando no PS4 via SSH ($SSH_TARGET)"
    REMOTE_TMP="/tmp/.ps4_chave.$$"

    typ="$(ssh_run 'id -u' 2>/dev/null || true)"
    [ -n "$typ" ] || die "não consegui conectar em $SSH_TARGET (PS4 ligado no Linux? IP certo? senha? use PS4_SSH_PASS=...)"
    if [ "$typ" != "0" ]; then
        echo "Aviso: conectado como usuário não-root (uid $typ); as escritas usam sudo."
        SUDO="sudo"
    else
        SUDO=""
    fi

    scp_put "$KEY_BIN" "$REMOTE_TMP" || die "falha ao copiar a chave para $SSH_TARGET"
    REMOTE_SHA="$(ssh_run "$SUDO install -d -m 700 -o root -g root '$DEST_DIR' && \
             $SUDO install -m 600 -o root -g root '$REMOTE_TMP' '$DEST_REL' && \
             rm -f '$REMOTE_TMP' && \
             $SUDO sha256sum '$DEST_REL'" 2>/dev/null | tail -1 | awk '{print $1}')" \
        || die "falha ao instalar $DEST_REL em $SSH_TARGET"

    [ -n "$REMOTE_SHA" ] || die "falha ao instalar $DEST_REL em $SSH_TARGET (sem resposta do sha256sum)"
    if [ "$REMOTE_SHA" = "$KEY_SHA" ]; then
        echo "✅ Instalada em $DEST_REL (sha256 confere)"
    else
        die "sha256 divergente após a instalação (local $KEY_SHA, remoto $REMOTE_SHA)"
    fi
else
    [ -n "$ROOTFS_DIR" ] || die "--rootfs exige um diretório"
    [ -d "$ROOTFS_DIR" ] || die "rootfs '$ROOTFS_DIR' não existe"
    [ -d "$ROOTFS_DIR/etc" ] || die "'$ROOTFS_DIR' não parece um rootfs (sem /etc)"

    if [ "$(id -u)" -ne 0 ]; then
        die "--rootfs precisa de root (use sudo) para gravar dono root e modo 600"
    fi

    echo "--> Instalando no rootfs $ROOTFS_DIR"
    install -d -m 700 -o root -g root "$ROOTFS_DIR$DEST_DIR"
    install -m 600 -o root -g root "$KEY_BIN" "$ROOTFS_DIR$DEST_REL"
    ls -l "$ROOTFS_DIR$DEST_REL"
fi

# ------------------------------------------------------------------------------
# 3. Verificação funcional (tenta montar o sda27 read-only)
# ------------------------------------------------------------------------------
if [ "$VERIFY" -eq 1 ] && [ "$MODE" = "ssh" ]; then
    echo ""
    echo "--> Verificando: montando sda27 (user/UFS2) read-only no PS4"
    if ssh_run "monta_particao.sh --check-key && monta_particao.sh 27 && mountpoint -q /mnt/ps4_internal/sda27" >/dev/null 2>&1; then
        echo "✅ Chave válida: sda27 montou em /mnt/ps4_internal/sda27"
        ssh_run "ls /mnt/ps4_internal/sda27" 2>/dev/null | head -10 || true
    else
        echo "⚠️  Não consegui montar o sda27 com essa chave."
        echo "    Causas prováveis: (a) a chave é de outro console; (b) HD interno"
        echo "    ausente/sem as partições esperadas; (c) falta o monta_particao.sh"
        echo "    (/usr/local/bin). A chave FOI gravada mesmo assim."
        echo "    Diagnostique com: ssh $SSH_TARGET 'monta_particao.sh 27'"
        VERIFY=2
    fi
elif [ "$VERIFY" -eq 1 ]; then
    echo ""
    echo "Info: verificação funcional só é feita no modo --ssh (o rootfs isolado"
    echo "      não tem o HD interno para testar)."
fi

echo ""
echo "========================================================="
echo "Próximos passos"
echo "========================================================="
if [ "$MODE" = "ssh" ]; then
    echo "  Montar agora (sem reboot): systemctl restart ps4-automount.service"
    echo "  Ver montagens:             ls -l /mnt/ps4_internal/"
else
    echo "  Desmonte o rootfs e ligue o PS4 — o ps4-automount.service monta no boot."
fi
echo "  Desmontar tudo:            desmonta_todas.sh"
echo "  Documentação:              others/docs/MONTAGEM_HD_INTERNO.md"
echo ""

if [ "${VERIFY:-1}" -eq 2 ]; then
    exit 3
fi
exit 0
