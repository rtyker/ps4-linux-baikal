#!/bin/sh
# Read-only dump of the MN864729 bridge registers through ICC 0x10/0.
# Each call sends ONE queue with ONE CMD_READ entry of 16 bytes (same format as cq_read in ps4_bridge.c).
# Reply layout (verified): 5 header bytes (res1 res2 unk1 unk2 count) + echo (count, addr_hi, addr_lo) + data.
# Output: "ADDR VALUE" lines (hex).
dump() { # $1 = start (hex), $2 = number of 16-byte rows
  s=$((0x$1)); n=$2; i=0
  while [ $i -lt $n ]; do
    a=$(printf '%04x' $((s + i * 16)))
    r=$(timeout 10 /tmp/icc_cmd raw 0x10 0 "040c00010108010110${a}00" --reply 48 --yes 2>&1 \
        | awk '/^reply/{f=1;next} f{for(k=1;k<=NF;k++) printf "%s ", $k}')
    set -- $r
    if [ $# -lt 24 ] || [ "$1$2" != "0000" ]; then echo "ERR $a $r"; i=$((i+1)); continue; fi
    shift 8
    j=0
    for v in "$@"; do
      [ $j -ge 16 ] && break
      printf '%04x %s\n' $((s + i * 16 + j)) "$v"; j=$((j+1))
    done
    i=$((i+1))
  done
}
dump 1000 4
dump 10c0 4
dump 1e00 1
dump 6000 3
dump 60f0 1
dump 6a00 1
dump 7000 16
dump 7200 3
dump 7400 1
dump 7600 16
dump 7a80 2
