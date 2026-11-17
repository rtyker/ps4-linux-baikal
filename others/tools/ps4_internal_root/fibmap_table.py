#!/usr/bin/env python3
"""Print a device-mapper "linear" table that maps a fully allocated file onto its physical blocks.

It asks the kernel where each block of FILE lives (the FIBMAP ioctl), merges runs of consecutive
blocks into extents, and prints one dm-linear line per extent:

    <logical start> <length> linear <DEVICE> <physical offset>        (all in 512-byte sectors)

DEVICE is only copied into the table text (for example /dev/mapper/ps4hdd); the script never opens it.
Nothing is ever written.

The table is only valid for the DEVICE the file system was read from (offsets are relative to the start
of that device) and only while the file is not deleted, moved, truncated or rewritten.

Run it as root while the file system that holds FILE is mounted (read-only is enough).

Exit status: 0 on success; 2 if the file is not safe to map (hole, partial block, extent beyond the device).

Example (on the console, with the Orbis user partition mounted read-only):
    fibmap_table.py /mnt/ps4_internal/sda27/data/linux/rootfs.img \\
        --device /dev/mapper/ps4hdd --device-sectors 1882449920 > rootfs.table
"""
import argparse
import fcntl
import hashlib
import os
import struct
import sys

FIBMAP = 1       # linux/fs.h: _IO(0x00, 1)
FIGETBSZ = 2     # linux/fs.h: _IO(0x00, 2)
SECTOR = 512


def ioctl_int(fd, request, value=0):
    """Call an ioctl whose argument is a pointer to a C int, and return the resulting int."""
    return struct.unpack("i", fcntl.ioctl(fd, request, struct.pack("i", value)))[0]


def fail(message):
    print("ERROR: " + message, file=sys.stderr)
    sys.exit(2)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file", help="fully allocated file to map")
    ap.add_argument("--device", required=True, help="device string to print in every table line")
    ap.add_argument("--device-sectors", type=int,
                    help="size of the device in 512-byte sectors; every extent must end inside it")
    ap.add_argument("--progress", action="store_true", help="print progress to stderr")
    args = ap.parse_args()

    fd = os.open(args.file, os.O_RDONLY)
    st = os.fstat(fd)
    size = st.st_size
    bsz = ioctl_int(fd, FIGETBSZ)
    if bsz < SECTOR or bsz % SECTOR:
        fail("unexpected file system block size %d" % bsz)
    if size == 0 or size % bsz:
        fail("file size %d is not a positive multiple of the block size %d" % (size, bsz))
    spb = bsz // SECTOR                      # sectors per file system block
    nblocks = size // bsz

    lines = []
    run_start = run_phys = run_len = None
    for i in range(nblocks):
        phys = ioctl_int(fd, FIBMAP, i)
        if phys == 0:
            fail("block %d maps to physical block 0 (a hole, or not allocated): the file must be fully written" % i)
        if run_len is not None and phys == run_phys + run_len:
            run_len += 1
        else:
            if run_len is not None:
                lines.append((run_start * spb, run_len * spb, run_phys * spb))
            run_start, run_phys, run_len = i, phys, 1
        if args.progress and i % 1000000 == 0:
            print("  block %d of %d" % (i, nblocks), file=sys.stderr)
    lines.append((run_start * spb, run_len * spb, run_phys * spb))

    total_sectors = nblocks * spb
    covered = sum(length for _, length, _ in lines)
    if covered != total_sectors:
        fail("internal check failed: extents cover %d sectors, expected %d" % (covered, total_sectors))
    if args.device_sectors is not None:
        for start, length, offset in lines:
            if offset + length > args.device_sectors:
                fail("extent at logical sector %d ends beyond the device (%d > %d)"
                     % (start, offset + length, args.device_sectors))

    text = "".join("%d %d linear %s %d\n" % (s, l, args.device, o) for s, l, o in lines)
    sys.stdout.write(text)
    print("file=%s size_bytes=%d fs_block_bytes=%d blocks=%d extents=%d total_sectors=%d table_sha256=%s"
          % (args.file, size, bsz, nblocks, len(lines), total_sectors,
             hashlib.sha256(text.encode()).hexdigest()), file=sys.stderr)


if __name__ == "__main__":
    main()
