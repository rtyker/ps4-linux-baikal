#!/bin/bash
# run_ghidra_geom_crypt.sh — Extract GEOM_CRYPT encryption pipeline functions
# from the Orbis kernel dump using Ghidra headless Java script.
#
# Uses the existing orbis_mts project (same binary as kmem_dump_1252.bin).
# Runs with -noanalysis to avoid the 15+ min DecompilerParameterID phase
# that caused the previous attempt to fail (see geom_crypt_analysis.log).
#
# Usage:
#   ./kernel/scripts/run_ghidra_geom_crypt.sh
#
# Output:
#   consolidado/decompiled/geom_crypt/*.c   (pseudocódigo de cada função)
#   consolidado/decompiled/geom_crypt/_SUMMARY.txt
#
# Log:
#   /tmp/ghidra_geom_crypt_YYYYMMDD_HHMMSS.log

set -euo pipefail

GHIDRA=/mnt/hdauxiliar/ghidra_12.1.2
# Frente 1 (kernel/): RE do dump Orbis. Caminhos derivados da localização do script
# (kernel/scripts/ -> kernel/consolidado/...), sem depender do nome do clone.
KERNEL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$KERNEL_DIR/consolidado/tools/ghidra_project"
PROJECT_NAME=orbis_mts
SCRIPT_DIR="$KERNEL_DIR/consolidado/tools/ghidra_scripts"
OUT_DIR="$KERNEL_DIR/consolidado/decompiled/geom_crypt"
LOG="/tmp/ghidra_geom_crypt_$(date +%Y%m%d_%H%M%S).log"

echo "============================================================"
echo "[$(date)] GEOM_CRYPT Pipeline Extraction (Java GhidraScript)"
echo "============================================================"
echo "  Ghidra:      $GHIDRA"
echo "  Project:     $PROJECT_DIR/$PROJECT_NAME"
echo "  Script:      $SCRIPT_DIR/ExtractGeomCryptPipeline.java"
echo "  Output dir:  $OUT_DIR"
echo "  Log:         $LOG"
echo "============================================================"

# Ensure output directory exists
mkdir -p "$OUT_DIR"

# Run Ghidra headless with Java script
"$GHIDRA/support/analyzeHeadless" \
    "$PROJECT_DIR" "$PROJECT_NAME" \
    -process kmem_dump_1252.bin \
    -noanalysis \
    -postScript ExtractGeomCryptPipeline.java \
    -scriptPath "$SCRIPT_DIR" \
    2>&1 | tee "$LOG"

echo ""
echo "============================================================"
echo "[$(date)] Extraction complete."
echo "============================================================"

# Show results
if [ -d "$OUT_DIR" ]; then
    FILE_COUNT=$(find "$OUT_DIR" -name "*.c" | wc -l)
    echo "  Files generated: $FILE_COUNT"
    echo "  Output dir: $OUT_DIR"
    if [ -f "$OUT_DIR/_SUMMARY.txt" ]; then
        echo ""
        echo "--- Summary (first 40 lines) ---"
        head -40 "$OUT_DIR/_SUMMARY.txt"
    fi
fi

echo ""
echo "  Full log: $LOG"
echo "============================================================"
