#!/bin/bash
# Encerra TODAS as capturas de UART em andamento (uart_capture.sh e os
# processos dd/stty/xxd internos que ele lanca), e limpa o pid file.
#
# Uso: uart_stop.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/../tests/uart_logs"
PID_FILE="$OUT_DIR/.uart_capture.pid"

FOUND=0

if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "[stop] encerrando captura registrada (PID $OLD_PID)"
        kill "$OLD_PID" 2>/dev/null
        FOUND=1
    fi
    rm -f "$PID_FILE"
fi

# mata qualquer uart_capture.sh orfao (sem pid file) e os processos
# internos (dd/xxd lendo /dev/ttyUSB*) que ele possa ter deixado presos
for pat in "uart_capture\.sh" "dd if=/dev/ttyUSB" "xxd -c 16"; do
    PIDS=$(pgrep -f "$pat" 2>/dev/null)
    if [ -n "$PIDS" ]; then
        echo "[stop] encerrando processos '$pat': $PIDS"
        kill $PIDS 2>/dev/null
        FOUND=1
    fi
done

sleep 0.5

# segunda passada com -9 para o que sobreviver ao SIGTERM
for pat in "uart_capture\.sh" "dd if=/dev/ttyUSB" "xxd -c 16"; do
    PIDS=$(pgrep -f "$pat" 2>/dev/null)
    if [ -n "$PIDS" ]; then
        echo "[stop] forcando encerramento (-9): $PIDS"
        kill -9 $PIDS 2>/dev/null
    fi
done

if [ "$FOUND" -eq 0 ]; then
    echo "[ok] nenhuma captura estava rodando"
else
    echo "[ok] captura(s) encerrada(s), porta serial livre"
fi
