#!/bin/sh
# Read-only: sample a few bridge registers N times. Usage: bridge_watch.sh N reg1 reg2 ...
n=$1; shift
i=0
while [ $i -lt $n ]; do
  line="$(date +%T.%N | cut -c1-12)"
  for a in "$@"; do
    v=$(timeout 10 /tmp/icc_cmd raw 0x10 0 "040c00010108010101${a}00" --reply 32 --yes 2>&1 \
        | awk '/^reply/{f=1;next} f{print $9; exit}')
    line="$line $a=$v"
  done
  echo "$line"
  i=$((i+1))
done
