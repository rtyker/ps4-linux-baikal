#!/bin/bash
# DP-2 stress on the PS4 console (no Xorg): N cycles of modeset (modetest), DPMS off/on (fb blank) and VT switch.
# Counts "clock recovery failed" in dmesg per step. Usage: ssh root@PS4 bash -s [N] < dp_stress.sh
N=${1:-50}; CONN=54; CRTC=42
cnt() { dmesg | grep -c "clock recovery failed"; }
base=$(cnt); echo "baseline clock-recovery-failed: $base"
fails=0
step() { # name, command...
  local n="$1"; shift; local b; b=$(cnt); "$@" >/dev/null 2>&1; sleep 1
  local a; a=$(cnt)
  if [ "$a" -gt "$b" ]; then echo "  FAIL cycle $i: $n (+$((a-b)))"; fails=$((fails+a-b)); fi
}
for i in $(seq 1 "$N"); do
  step mode720   timeout 2 modetest -s $CONN@$CRTC:1280x720
  step mode1080  timeout 2 modetest -s $CONN@$CRTC:1920x1080
  step dpms_off_on bash -c 'echo 1 > /sys/class/graphics/fb0/blank; sleep 1; echo 0 > /sys/class/graphics/fb0/blank'
  step chvt      bash -c 'chvt 2; sleep 0.5; chvt 1'
  echo "cycle $i done (total new failures: $fails)"
done
echo "== RESULT: $fails new 'clock recovery failed' in $N cycles; dmesg total $(cnt) (baseline $base)"
dmesg | grep -iE "oops|BUG:|Call Trace|mode not available" | tail -3
