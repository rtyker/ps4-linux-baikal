#!/bin/bash
# Hook: on_error
# Envia notificação de erro crítico

source "$HOME/scripts/notifica.sh"

ERROR_MSG="${1:-Erro desconhecido no build/deploy do PS4}"
CONTEXT="${2:-}"

MSG="❌ Erro: $ERROR_MSG"
[[ -n "$CONTEXT" ]] && MSG="$MSG ($CONTEXT)"

"$HOME/scripts/notifica.sh" -t "PS4 Kernel/Deploy" -p urgente "$MSG"