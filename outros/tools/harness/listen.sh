#!/usr/bin/env bash
# listen.sh – start the kernel dump receiver (receive_kmem_dump.py)
# Usage: ./listen.sh [PS4_IP] [PORT] [START] [SIZE] [OUT]
# If arguments are omitted defaults from receive_kmem_dump.py are used.

# Default parameters (same as receive_kmem_dump.py)
PS4_IP=${1:-192.168.6.130}
PORT=${2:-9020}
START=${3:-0}
SIZE=${4:-0x2034af0}
OUT=${5:-"kmem_dump_${START}.bin"}

# Resolve script directory (the repository root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run the Python receiver using the defaults or supplied arguments
python3 "$SCRIPT_DIR/ps4-linux-payloads/receive_kmem_dump.py" "$START" "$SIZE" "$OUT"
