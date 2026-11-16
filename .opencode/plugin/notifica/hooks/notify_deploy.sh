#!/bin/bash
# Hook: on_deploy_complete
# Envia notificação quando o deploy no PS4 completa

source "$HOME/scripts/notifica.sh"

STATUS="${1:-success}"
DETAILS="${2:-Deploy no PS4 concluído}"

if [[ "$STATUS" == "success" ]]; then
    "$HOME/scripts/notifica.sh" -t "PS4 Deploy" -p high "🚀 Deploy concluído: $DETAILS"
else
    "$HOME/scripts/notifica.sh" -t "PS4 Deploy" -p urgente "💥 Deploy falhou: $DETAILS"
fi