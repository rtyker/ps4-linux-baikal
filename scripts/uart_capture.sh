#!/bin/bash
# Captura UART robusta usando o metodo comprovado pelo usuario (stty + dd).
# Grava bytes crus continuamente, com hexdump ao vivo, e reinicia sozinho
# se a porta cair/reconectar.
#
# Uso: uart_capture.sh [duracao_segundos] [arquivo_saida.bin]

set -u

BAUD=115200
DUR="${1:-300}"
OUT="${2:-uart_capture.bin}"
LOG="${OUT%.bin}.log"

: > "$OUT"
: > "$LOG"

find_port() {
    ls /dev/ttyUSB* 2>/dev/null | head -1
}

echo "[inicio] /dev/ttyUSB* @ $BAUD raw | duracao ${DUR}s -> $OUT (log: $LOG)" | tee -a "$LOG"

END=$(( $(date +%s) + DUR ))

while [ "$(date +%s)" -lt "$END" ]; do
    PORT=$(find_port)
    if [ -z "$PORT" ]; then
        echo "[$(date +%T)] nenhuma /dev/ttyUSB* presente, aguardando..." | tee -a "$LOG"
        sleep 1
        continue
    fi

    stty -F "$PORT" "$BAUD" raw -echo -icanon -ixon -ixoff -crtscts 2>/dev/null
    if [ $? -ne 0 ]; then
        sleep 0.5
        continue
    fi
    echo "[$(date +%T)] usando $PORT" >> "$LOG"

    REMAINING=$(( END - $(date +%s) ))
    [ "$REMAINING" -le 0 ] && break

    # dd le bytes crus continuamente ate timeout/erro/porta cair;
    # timeout finaliza o dd sem matar o loop externo.
    timeout "$REMAINING" dd if="$PORT" bs=1 2>/dev/null | \
        tee -a "$OUT" | \
        xxd -c 16 | \
        while IFS= read -r line; do
            echo "[$(date +%T)] $line" >> "$LOG"
        done

    # se chegou aqui antes do fim da janela, a porta provavelmente caiu
    sleep 0.3
done

TOTAL=$(stat -c %s "$OUT" 2>/dev/null || echo 0)
echo "[fim] total capturado: $TOTAL bytes" | tee -a "$LOG"
