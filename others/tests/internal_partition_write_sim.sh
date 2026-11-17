#!/bin/bash
# Write simulation on an internal partition using a dm-snapshot whose copy-on-write store is in RAM (tmpfs).
# Usage: bash -s <partition number> <fstype-opt> < snap_sim.sh   e.g. 25 vfat
# The real partition is only READ (hashed before and after); every write lands in /dev/shm.
set -u
N="${1:?partition number}"
KIND="${2:?vfat|ufs2}"
ORIGIN="ps4_sda${N}_origin"
SNAP="ps4_sda${N}_snap"
COW=/dev/shm/cow_sda${N}.img
MNT=/mnt/ps4_sim${N}
LOOP=""

cleanup() {
  umount "$MNT" 2>/dev/null
  dmsetup remove "$SNAP" 2>/dev/null
  dmsetup remove "$ORIGIN" 2>/dev/null
  [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
  rm -f "$COW"
  rmdir "$MNT" 2>/dev/null
}
trap cleanup EXIT

SECT=$(blockdev --getsz /dev/sda${N})
echo "partition sda${N}: $SECT sectors"

echo "== 1. hash of the whole REAL partition before"
H1=$(dd if=/dev/sda${N} bs=4M status=none | sha256sum | cut -c1-16)
echo "   before: $H1"

echo "== 2. unmount the read-only mount and build origin (rw table, key never printed) + RAM snapshot"
umount /mnt/ps4_internal/sda${N} || { echo "could not unmount sda${N}"; exit 1; }
dmsetup table --showkeys ps4_sda${N} | dmsetup create "$ORIGIN" || { echo "origin failed"; exit 1; }
truncate -s 1G "$COW"
LOOP=$(losetup -f --show "$COW")
dmsetup create "$SNAP" --table "0 $SECT snapshot /dev/mapper/$ORIGIN $LOOP N 8" || { echo "snapshot failed"; exit 1; }
dmsetup info -c --noheadings -o name,attr "$ORIGIN" "$SNAP"

echo "== 3. mount READ-WRITE on the snapshot"
mkdir -p "$MNT"
if [ "$KIND" = vfat ]; then
  mount -t vfat -o rw,noatime,fmask=0022,dmask=0022 /dev/mapper/$SNAP "$MNT"
else
  mount -t ufs -o rw,noatime,ufstype=ufs2,onerror=lock /dev/mapper/$SNAP "$MNT"
fi
RC=$?
grep " $MNT " /proc/mounts | cut -c1-110
dmesg | tail -4 | cut -c1-140
if [ $RC -ne 0 ]; then echo "RW MOUNT FAILED rc=$RC"; fi

if [ $RC -eq 0 ]; then
  echo "== 4. write tests (land in RAM only)"
  mkdir -p "$MNT/sim_test"
  head -c 200M /dev/urandom > /tmp/sim_src.bin
  S1=$(sha256sum < /tmp/sim_src.bin | cut -c1-16)
  cp /tmp/sim_src.bin "$MNT/sim_test/big.bin"; echo "   copy rc=$?"
  for i in 1 2 3; do echo "file $i" > "$MNT/sim_test/small_$i.txt"; done
  sync
  umount "$MNT"; echo "   umount rc=$?"
  if [ "$KIND" = vfat ]; then
    mount -t vfat -o ro /dev/mapper/$SNAP "$MNT"
  else
    mount -t ufs -o ro,ufstype=ufs2 /dev/mapper/$SNAP "$MNT"
  fi
  S2=$(sha256sum < "$MNT/sim_test/big.bin" | cut -c1-16)
  echo "   written $S1 | read back after remount $S2 | $([ "$S1" = "$S2" ] && echo IDENTICAL || echo DIFFERENT)"
  ls -l "$MNT/sim_test" | tail -5
  echo "   COW usage: $(dmsetup status "$SNAP")"
  umount "$MNT"
  rm -f /tmp/sim_src.bin
fi

echo "== 5. tear down the simulation, then hash the REAL partition again"
cleanup
trap - EXIT
H2=$(dd if=/dev/sda${N} bs=4M status=none | sha256sum | cut -c1-16)
echo "   after:  $H2"
[ "$H1" = "$H2" ] && echo "RESULT: real partition UNCHANGED" || echo "RESULT: REAL PARTITION CHANGED!"
echo "== 6. restore the normal read-only mounts"
systemctl restart ps4-automount.service
mount | grep "ps4_internal/sda${N}" | cut -c1-90
