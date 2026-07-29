#!/bin/bash
# Hook: on_build_complete
# Envia notificação quando o build do kernel completa

source "$HOME/scripts/notifica.sh"

# Argumentos passados pelo opencode: $1 = status (success/failure), $2 = detalhes
STATUS="${1:-success}"
DETAILS="${2:-Build do kernel 7.0 concluído}"

if [[ "$STATUS" == "success" ]]; then
    "$HOME/scripts/notifica.sh" -t "PS4 Kernel Build" -p high "✅ Build concluído: $DETAILS"
else
    "$HOME/scripts/notifica.sh" -t "PS4 Kernel Build" -p urgente "❌ Build falhou: $DETAILS"
fi