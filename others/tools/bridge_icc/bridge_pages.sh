#!/bin/sh
# Read-only: probe the first 16 bytes of every 0x100 page from 0x0000 to 0x7f00 to find live pages.
# Output: "PAGE status first-16-bytes"
p=0
while [ $p -lt 128 ]; do
  h=$(printf '%02x00' $p)
  r=$(timeout 10 /tmp/icc_cmd raw 0x10 0 "040c00010108010110${h}00" --reply 48 --yes 2>&1 \
      | awk '/^reply/{f=1;next} f{for(k=1;k<=NF;k++) printf "%s ", $k}')
  set -- $r
  if [ $# -lt 24 ] || [ "$1$2" != "0000" ]; then echo "$h ERR $r"; else shift 8; echo "$h ok $*" | cut -c1-60; fi
  p=$((p+1))
done
