#!/bin/bash
# Inicia UMA captura de UART em background, gravando em tests/uart_logs/.
# Recusa iniciar se ja houver uma captura rodando (evita duas capturas
# disputando a mesma porta serial, que corrompe/trava os dados).
#
# Uso: uart_start.sh [duracao_segundos] [nome_opcional]
#
# Exemplos:
#   scripts/uart_start.sh                      # 300s, nome automatico
#   scripts/uart_start.sh 900                  # 15 min
#   scripts/uart_start.sh 900 s5-shutdown-test # 15 min, nome customizado

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPTURE_BIN="$SCRIPT_DIR/uart_capture.sh"
OUT_DIR="$SCRIPT_DIR/../tests/uart_logs"
PID_FILE="$OUT_DIR/.uart_capture.pid"

DUR="${1:-300}"
NAME="${2:-uart}"
TS=$(date +%Y%m%d_%H%M%S)
BASENAME="${NAME}_${TS}"

mkdir -p "$OUT_DIR"

if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[erro] ja existe uma captura rodando (PID $OLD_PID)." >&2
        echo "       rode scripts/uart_stop.sh antes de iniciar outra." >&2
        exit 1
    fi
    rm -f "$PID_FILE"
fi

# tambem verifica por processos orfaos do uart_capture.sh que nao tenham
# deixado pid file (ex: sessao anterior encerrada sem uart_stop.sh)
if pgrep -f "uart_capture\.sh" >/dev/null 2>&1; then
    echo "[erro] ja existe(m) processo(s) uart_capture.sh rodando sem pid file:" >&2
    pgrep -af "uart_capture\.sh" >&2
    echo "       rode scripts/uart_stop.sh antes de iniciar outra captura." >&2
    exit 1
fi

OUT_BIN="$OUT_DIR/${BASENAME}.bin"
OUT_STDOUT="$OUT_DIR/${BASENAME}_stdout.log"

setsid nohup "$CAPTURE_BIN" "$DUR" "$OUT_BIN" > "$OUT_STDOUT" 2>&1 < /dev/null &
CAPTURE_PID=$!
disown 2>/dev/null

echo "$CAPTURE_PID" > "$PID_FILE"

sleep 1
if ! kill -0 "$CAPTURE_PID" 2>/dev/null; then
    echo "[erro] captura nao iniciou (verifique $OUT_STDOUT)" >&2
    rm -f "$PID_FILE"
    exit 1
fi

echo "[ok] captura iniciada (PID $CAPTURE_PID), duracao ${DUR}s"
echo "     bin: $OUT_BIN"
echo "     log: ${OUT_BIN%.bin}.log"
echo "     pid file: $PID_FILE"
echo ""
echo "Para acompanhar ao vivo: tail -f ${OUT_BIN%.bin}.log"
echo "Para encerrar antes do fim: scripts/uart_stop.sh"
