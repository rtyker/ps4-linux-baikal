#!/bin/bash
# Build and run the host test of mtsx_desc.h. No kernel, no hardware.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
cc -std=c11 -Wall -Wextra -Werror -O2 -fsanitize=address,undefined \
   -I"$HERE/../../../kernel/drivers_mts" \
   -o "$OUT/test_desc" "$HERE/test_desc.c"
"$OUT/test_desc"
