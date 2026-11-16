#!/bin/bash
# Executar no PC (192.168.0.1) antes de cada teste
LOG_DIR="$HOME/ps4_logs"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/netconsole_$(date +%Y%m%d_%H%M%S).log"
echo "=== Escutando netconsole na porta 6666 ==="
echo "=== Logs em: $LOGFILE ==="
echo "=== Ctrl+C para parar ==="
nc -u -l -p 6666 | tee -a "$LOGFILE"
