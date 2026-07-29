#!/usr/bin/env bash
# webhost_stop.sh — derruba o Web-Host (DNS+HTTP) criado por webhost_start.sh
# Uso: sudo ./scripts/webhost_stop.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERRO: rode com sudo (precisa matar :53 e :80 e remover fw rules)." >&2
    exit 1
fi

PID_DIR="/tmp/ps4-webhost-pids"

for name in dnsmasq http; do
    pidfile="$PID_DIR/$name.pid"
    if [[ -f "$pidfile" ]]; then
        pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            echo "[$name] pid=$pid finalizado"
        else
            echo "[$name] pid=$pid já morto"
        fi
        rm -f "$pidfile"
    fi
done

# Backup: matar processos órfãos por nome/porta (caso pidfile esteja desatualizado)
pkill -f "dnsmasq --no-daemon --listen-address=192.168.6.100" 2>/dev/null || true
pkill -f "python3 -m http.server 80 --bind 192.168.6.100"     2>/dev/null || true

# Remover regras de firewall criadas pelo start (idempotente)
SUBNET="192.168.6.0/24"
if command -v iptables >/dev/null 2>&1; then
    iptables -D INPUT -s "$SUBNET" -p udp --dport 53 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -s "$SUBNET" -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
fi
# nft: regras não têm handle aqui — recomenda-se purge manual se estritamente
# necessário; a chain inet input normalmente sobrevive sem as regras adicionadas.

echo "Web-Host parado (DNS :53 e HTTP :80 em 192.168.6.100)."
