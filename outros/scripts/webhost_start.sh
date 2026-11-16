#!/usr/bin/env bash
# webhost_start.sh — sobe Web-Host local para trigger JB PS4 12.52 via User Guide
#
# Arquitetura (ver PLANO_MIGRACAO_WEBHOST_12.52.md):
#   - dnsmasq em :53/udp  → manuals.playstation.net / guides.elpes4.net → 192.168.6.100
#   - python http.server em :80/tcp → serve /opt/ps4-webhost/html
#
# Pré-requisitos:
#   - PC host com wlp0s20f3 ativa em 192.168.6.100/24 (mesma subnet WiFi do PS4)
#   - pacman -S dnsmasq python3
#   - /opt/ps4-webhost/html/index.html (PSFree) + /opt/ps4-webhost/payloads/goldhen_1252.bin
#
# Uso:
#   sudo ./scripts/webhost_start.sh
#
# Logs em /tmp/ps4-webhost-{dns,http}.log
# Para parar: sudo ./scripts/webhost_stop.sh

set -euo pipefail

# ─── Config (fixa — topologia validada no AGENTS.md) ─────────────────────────
HOST_IP="192.168.6.100"           # PC host (wlp0s20f3), mesma subnet do PS4 WiFi
PS4_IP="192.168.6.128"            # PS4 (reserva DHCP conhecida — não usada aqui)
SUBNET="192.168.6.0/24"
DNS_PORTS=("manuals.playstation.net" "guides.elpes4.net" "manuals.gaming.playstation.net")
WEBROOT="/opt/ps4-webhost/html"
PAYLOAD_DIR="/opt/ps4-webhost/payloads"
LOG_DIR="/tmp"
PID_DIR="/tmp/ps4-webhost-pids"
mkdir -p "$PID_DIR"

# ─── Pré-checagens ───────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "ERRO: rode com sudo (precisa de :53 e :80)." >&2
    exit 1
fi

if ! command -v dnsmasq >/dev/null; then
    echo "ERRO: dnsmasq não instalado. Rode: sudo pacman -S dnsmasq python3" >&2
    exit 1
fi
if ! command -v python3 >/dev/null; then
    echo "ERRO: python3 não instalado. Rode: sudo pacman -S dnsmasq python3" >&2
    exit 1
fi

if [[ ! -f "$WEBROOT/index.html" ]]; then
    echo "ERRO: $WEBROOT/index.html não encontrado." >&2
    echo "       Coloque aí o HTML do PSFree (FW 12.52)." >&2
    echo "       Payloads em $PAYLOAD_DIR/goldhen_1252.bin" >&2
    exit 1
fi

# Interfaces — validar que HOST_IP está realmente em alguma interface
if ! ip -4 addr show | grep -qw "$HOST_IP"; then
    echo "ERRO: $HOST_IP não está em nenhuma interface do PC host." >&2
    echo "       Configure a interface WiFi (wlp0s20f3) com IP estático $HOST_IP/24." >&2
    exit 1
fi

# ─── Stop prévio (idempotente) ───────────────────────────────────────────────
"$(dirname "$0")/webhost_stop.sh" 2>/dev/null || true

# ─── dnsmasq (DNS hijack) ────────────────────────────────────────────────────
# Escuta :53/udp só na interface com HOST_IP
DNS_LOG="$LOG_DIR/ps4-webhost-dns.log"
DNS_ARGS=()
for domain in "${DNS_PORTS[@]}"; do
    DNS_ARGS+=(--address="/${domain}/${HOST_IP}")
done
dnsmasq --no-daemon \
        --listen-address="$HOST_IP" \
        --bind-interfaces \
        --no-resolv \
        --no-hosts \
        --log-queries \
        --log-facility="$DNS_LOG" \
        "${DNS_ARGS[@]}" \
        >/dev/null 2>&1 &
DNS_PID=$!
echo "$DNS_PID" > "$PID_DIR/dnsmasq.pid"
echo "[dns] dnsmasq pid=$DNS_PID em $HOST_IP:53"
echo "[dns] domínios hijack: ${DNS_PORTS[*]}"

# ─── python http.server (porta 80) ─────────────────────────────────────────
HTTP_LOG="$LOG_DIR/ps4-webhost-http.log"
cd "$WEBROOT/.."  # subir do dir PAI pra /opt/ps4-webhost/html/ e /payloads/ acessíveis
python3 -m http.server 80 --bind "$HOST_IP" --directory "$WEBROOT" >"$HTTP_LOG" 2>&1 &
HTTP_PID=$!
echo "$HTTP_PID" > "$PID_DIR/http.pid"
echo "[http] python http.server pid=$HTTP_PID em $HOST_IP:80 servindo $WEBROOT"

# ─── Firewall (libera subnet WiFi; mantém eth0/enp60s0 isolada do teste GBE)
FW_RULE_ADDED=()
add_fw() {
    local proto="$1" port="$2"
    if command -v nft >/dev/null 2>&1; then
        # nft: adiciona na chain input do filter
        nft add rule inet filter input ip saddr "$SUBNET" "$proto" dport "$port" accept 2>/dev/null || true
    fi
    if command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -s "$SUBNET" -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
    fi
    FW_RULE_ADDED+=("$proto/$port")
}
add_fw udp 53
add_fw tcp 80
echo "[fw] regras adicionadas: ${FW_RULE_ADDED[*]} (subnet $SUBNET)"

# ─── Resumo final ────────────────────────────────────────────────────────────
echo
echo "Web-Host ativo. Agora no PS4:"
echo "  1. Configurações > Rede > WiFi > Personalizada"
echo "  2. DNS primário: $HOST_IP"
echo "  3. Menu inicial > User Guide / Manual do Usuário"
echo
echo "Logs:"
echo "  DNS : tail -f $DNS_LOG"
echo "  HTTP: tail -f $HTTP_LOG"
echo
echo "Para parar: sudo ./scripts/webhost_stop.sh"
