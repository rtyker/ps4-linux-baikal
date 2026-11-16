#!/usr/bin/env bash
# ps4_send_payload.sh — envia um payload ELF (ou puxa arquivos) do PS4 em Orbis.
#
# Procedimento canônico: others/docs/ENVIO_DE_PAYLOADS.md
#
# O PS4 só aceita payload de loader quando está rodando **Orbis** (GoldHEN ativo).
# Depois do kexec para Linux, as portas 9090/2121 não existem mais.
#
# ⚠️ O IP MUDA entre os ambientes (mesmo WiFi DHCP, MACs diferentes):
#   Orbis + GoldHEN  → 192.168.6.130   (MAC 6A:FA:C4:EA:34:9C)  ← alvo DESTE script
#   Linux pós-kexec  → 192.168.6.128   (SSH root/ps4; NÃO tem loader)
#
# Portas do GoldHEN (confirmadas no README oficial do GoldHEN):
#   9090  BinLoader  (aceita UMA única conexão por sessão)
#   2121  FTP        (anônimo, usado para recuperar arquivos do console)
#   3232  klog
#
# 9020/9021 pertencem ao `elfldr` do ps4-payload-dev (outro loader, não é o GoldHEN).
#
# Uso:
#   ./ps4_send_payload.sh <payload.bin> [--ip IP] [--port 9090] [--timeout 10]
#   ./ps4_send_payload.sh --check [--ip IP]
#   ./ps4_send_payload.sh --ftp-get /data/hddeap/eap_hdd_key.bin [--out ./eap_hdd_key.bin]
#
# Exemplos:
#   # chave EAP (EAPDumper compilado em others/tools/ps4_hdd_tools/)
#   ./ps4_send_payload.sh ../tools/ps4_hdd_tools/EAPDumper/EAPDumper.bin
#   ./ps4_send_payload.sh --ftp-get /data/hddeap/eap_hdd_key.bin
#
# ⚠️ NUNCA teste a porta com `nc -z`/`telnet`: o BinLoader tem accept() único e o
#    teste consome a conexão. Este script usa apenas `ping` para checar presença.
#
set -euo pipefail

PS4_IP="${PS4_IP:-192.168.6.130}"     # Orbis + GoldHEN (Linux usa .128)
PS4_LINUX_IP="${PS4_LINUX_IP:-192.168.6.128}"  # só para avisar "esse é o Linux"
PAYLOAD_PORT="${PS4_PAYLOAD_PORT:-9090}"
FTP_PORT="${PS4_FTP_PORT:-2121}"
TIMEOUT="${PS4_PAYLOAD_TIMEOUT:-10}"

DO_PING=1
CHECK_ONLY=0
PAYLOAD=""
FTP_GET=""
FTP_OUT=""

die() { echo "ERRO: $*" >&2; exit 1; }

usage() {
    awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --ip)         PS4_IP="$2"; shift 2 ;;
        --port)       PAYLOAD_PORT="$2"; shift 2 ;;
        --timeout)    TIMEOUT="$2"; shift 2 ;;
        --ftp-get)    FTP_GET="$2"; shift 2 ;;
        --out)        FTP_OUT="$2"; shift 2 ;;
        --no-ping)    DO_PING=0; shift ;;
        --check)      CHECK_ONLY=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        -*)           die "opção desconhecida: $1 (use --help)" ;;
        *)
            [ -z "$PAYLOAD" ] || die "payload especificado duas vezes: '$PAYLOAD' e '$1'"
            PAYLOAD="$1"; shift ;;
    esac
done

if [ "$CHECK_ONLY" = 0 ] && [ -z "$PAYLOAD" ] && [ -z "$FTP_GET" ]; then
    usage >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# 1. Pré-requisitos
# ---------------------------------------------------------------------------
if [ -n "$PAYLOAD" ]; then
    command -v socat >/dev/null || die "socat não instalado (sudo pacman -S socat / apt install socat)"
    [ -f "$PAYLOAD" ] || die "payload não encontrado: $PAYLOAD"
    [ -r "$PAYLOAD" ] || die "payload sem permissão de leitura: $PAYLOAD"
    [ -s "$PAYLOAD" ] || die "payload vazio: $PAYLOAD"

    if ! command -v readelf >/dev/null; then
        echo "AVISO: readelf ausente; pulando validação de ELF." >&2
    else
        HDR="$(readelf -h "$PAYLOAD" 2>/dev/null || true)"
        [ -n "$HDR" ] || die "não é um ELF válido (readelf falhou): $PAYLOAD"
        echo "$HDR" | grep -q 'ELF64'  || die "payload não é ELF64: $PAYLOAD"
        echo "$HDR" | grep -q 'X86-64' || die "payload não é x86-64: $PAYLOAD"
        echo "$HDR" | grep -Eq 'DYN|EXEC' || die "payload com tipo ELF inesperado: $PAYLOAD"
    fi

    SIZE=$(stat -c %s "$PAYLOAD")
    if [ "$SIZE" -gt 8388608 ]; then
        echo "AVISO: payload com $SIZE bytes (> 8 MiB) — loaders do PS4 podem rejeitar." >&2
    fi
fi

if [ -n "$FTP_GET" ]; then
    command -v curl >/dev/null || die "curl não instalado"
    case "$FTP_GET" in
        /*) ;;
        *) die "--ftp-get exige caminho absoluto no console (ex: /data/hddeap/eap_hdd_key.bin)" ;;
    esac
fi

# ---------------------------------------------------------------------------
# 2. Presença do console (só ICMP — nunca connect() na porta do loader)
# ---------------------------------------------------------------------------
if [ "$DO_PING" = 1 ]; then
    if ping -c 3 -W 1 "$PS4_IP" >/dev/null 2>&1; then
        echo "PS4 responde em $PS4_IP (ICMP OK) — esperado do Orbis/GoldHEN"
        echo "    ATENÇÃO: ICMP OK NÃO prova que o BinLoader está ativo; a prova é o"
        echo "    envio dar certo + a notificação na TV do PS4."
    elif [ "$PS4_IP" != "$PS4_LINUX_IP" ] && ping -c 2 -W 1 "$PS4_LINUX_IP" >/dev/null 2>&1; then
        # O IP .128 é o do Linux pós-kexec: o console está ligado, mas no ambiente errado.
        die "o PS4 responde em $PS4_LINUX_IP — esse é o IP do **Linux** pós-kexec, onde NÃO existe loader.
     Reinicie o console no Orbis, ative o GoldHEN e rode de novo (alvo correto: $PS4_IP).
     Se o Orbis estiver em outro IP, use --ip <ip>. Para SSH no Linux: sshpass -p ps4 ssh root@$PS4_LINUX_IP"
    else
        if [ "$CHECK_ONLY" = 1 ]; then
            die "PS4 não responde a ping em $PS4_IP (Orbis) nem em $PS4_LINUX_IP (Linux): console desligado, fora da rede, IP mudou (use --ip) ou ICMP bloqueado (use --no-ping)"
        fi
        die "PS4 não responde a ping em $PS4_IP (Orbis) nem em $PS4_LINUX_IP (Linux). Confira: console ligado no Orbis, GoldHEN ativo, mesma rede. Se ICMP estiver bloqueado, repita com --no-ping."
    fi
fi

if [ "$CHECK_ONLY" = 1 ]; then
    echo "Pré-requisitos OK (nada foi enviado)."
    [ -n "$PAYLOAD" ] && echo "  payload : $PAYLOAD ($SIZE bytes)"
    echo "  destino : $PS4_IP porta $PAYLOAD_PORT (BinLoader) · FTP $FTP_PORT"
    exit 0
fi

# ---------------------------------------------------------------------------
# 3. Envio do payload (BinLoader)
# ---------------------------------------------------------------------------
if [ -n "$PAYLOAD" ]; then
    echo "=== Enviando payload para $PS4_IP:$PAYLOAD_PORT (BinLoader do GoldHEN) ==="
    echo "    arquivo: $PAYLOAD ($SIZE bytes)"
    # -t: espera o servidor fechar a conexão após carregar o ELF.
    if ! socat -t "$TIMEOUT" - TCP:"$PS4_IP":"$PAYLOAD_PORT" < "$PAYLOAD"; then
        cat >&2 <<EOF
ERRO: o envio falhou.

Causas prováveis (em ordem de frequência):
  1. O PS4 NÃO está no Orbis. Depois do kexec para Linux não existe BinLoader —
     reinicie o console, entre no Orbis e ative o GoldHEN.
     (No Orbis o IP é 192.168.6.130; no Linux é 192.168.6.128.)
  2. GoldHEN sem BinLoader ligado (Settings → "Enable BinLoader Server", porta 9090).
  3. **Você já rodou um dumper de memória (ex: EAPDumper) neste console e não reiniciou** —
     a memória do Orbis fica travada; faça reboot antes de tentar outro envio ou FTP.
  4. IP errado (use --ip) ou console em outra rede.
  4. O accept() único já foi consumido por um envio/probe anterior nesta sessão
     do GoldHEN — reinicie o BinLoader (ou o payload que ficou escutando).
  5. Payload incompatível com o firmware — a notificação na TV (canto superior
     esquerdo) mostra se ele chegou a rodar.
EOF
        exit 1
    fi
    echo "Envio concluído (sem erro de transporte)."
    echo "Confira a notificação na TV do PS4 antes de assumir sucesso."
fi

# ---------------------------------------------------------------------------
# 4. Recuperação de arquivos (FTP do GoldHEN)
# ---------------------------------------------------------------------------
if [ -n "$FTP_GET" ]; then
    [ -n "$FTP_OUT" ] || FTP_OUT="$(basename "$FTP_GET")"
    echo "=== Baixando ftp://$PS4_IP:$FTP_PORT$FTP_GET -> $FTP_OUT ==="
    if ! curl --fail --silent --show-error --connect-timeout 5 --max-time 120 \
              "ftp://$PS4_IP:$FTP_PORT$FTP_GET" -o "$FTP_OUT"; then
        cat >&2 <<EOF
ERRO: download por FTP falhou.

Causas prováveis:
  1. O PS4 não está no Orbis, ou o FTP do GoldHEN está desligado (porta 2121).
  2. O caminho não existe no console — o payload ainda não rodou/gravou.
  3. IP errado (use --ip).
EOF
        exit 1
    fi
    ls -l "$FTP_OUT"
    sha256sum "$FTP_OUT"
fi
