#!/bin/bash
# Compila icc_cmd estático para o PS4 (x86_64). Ver README.md.
set -euo pipefail
cd "$(dirname "$0")"
gcc -O2 -Wall -Wextra -static -o icc_cmd icc_cmd.c
file icc_cmd
sha256sum icc_cmd
