#!/bin/sh
# Read-only: dump bridge registers from START to END (hex, inclusive start, exclusive end), 16 bytes per ICC call.
# Usage: bridge_range.sh START END  -> "ADDR VALUE" lines; unreadable rows -> "ERR ADDR <reply>"
s=$((0x$1)); e=$((0x$2)); a=$s
while [ $a -lt $e ]; do
  h=$(printf '%04x' $a)
  r=$(timeout 10 /tmp/icc_cmd raw 0x10 0 "040c00010108010110${h}00" --reply 48 --yes 2>&1 \
      | awk '/^reply/{f=1;next} f{for(k=1;k<=NF;k++) printf "%s ", $k}')
  set -- $r
  if [ $# -lt 24 ] || [ "$1$2" != "0000" ]; then echo "ERR $h $r"; a=$((a+16)); continue; fi
  shift 8; j=0
  for v in "$@"; do [ $j -ge 16 ] && break; printf '%04x %s\n' $((a + j)) "$v"; j=$((j+1)); done
  a=$((a+16))
done
