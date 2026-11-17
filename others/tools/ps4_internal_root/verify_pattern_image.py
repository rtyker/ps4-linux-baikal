#!/usr/bin/env python3
"""Check a patterned image (see gen_pattern_image.py) read through a block map or directly from a file.

Mode 1, through a dm-linear table, reading the underlying device directly (read-only):
    verify_pattern_image.py --table rootfs.table --device /dev/mapper/ps4hdd \\
        --size-bytes 8589934592 --nonce <32 hex chars>

Mode 2, a plain file or block device read from offset 0 (for example the linear device itself):
    verify_pattern_image.py --file /dev/mapper/ps4root_test --size-bytes 8589934592 --nonce <32 hex chars>

--sample STEP checks only every STEP-th sector (quick check). Without it, every sector is checked.
That full pass is what proves a block map: a sector that holds the right index and the right nonce can
only be part of the uploaded file, in the right position.

The script only reads. Exit status: 0 = all checked sectors are correct, 1 = mismatch, 2 = bad usage.
"""
import argparse
import os
import struct
import sys

MAGIC = b"PS4IMG01"
SECTOR = 512
CHUNK_SECTORS = 2048


def parse_table(path):
    extents = []
    with open(path) as f:
        for n, line in enumerate(f, 1):
            parts = line.split()
            if not parts:
                continue
            if len(parts) != 5 or parts[2] != "linear":
                sys.exit("ERROR: table line %d is not a dm-linear line: %r" % (n, line.strip()))
            extents.append((int(parts[0]), int(parts[1]), int(parts[4])))
    expected = 0
    for start, length, _ in extents:
        if start != expected:
            sys.exit("ERROR: the table has a gap or overlap at logical sector %d" % expected)
        expected += length
    return extents, expected


def header(index, nonce):
    return MAGIC + struct.pack("<Q", index) + nonce


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--table", help="dm-linear table (needs --device)")
    src.add_argument("--file", help="file or block device holding the image from offset 0")
    ap.add_argument("--device", help="device or file the table offsets refer to")
    ap.add_argument("--size-bytes", type=int, required=True)
    ap.add_argument("--nonce", required=True, help="32 hex characters")
    ap.add_argument("--sample", type=int, default=1, help="check every STEP-th sector (default 1 = all)")
    args = ap.parse_args()

    if len(args.nonce) != 32:
        sys.exit("ERROR: --nonce needs exactly 32 hex characters")
    nonce = bytes.fromhex(args.nonce)
    if args.size_bytes % SECTOR:
        sys.exit("ERROR: --size-bytes must be a multiple of 512")
    total_sectors = args.size_bytes // SECTOR
    step = max(1, args.sample)

    if args.table:
        if not args.device:
            sys.exit("ERROR: --table needs --device")
        extents, covered = parse_table(args.table)
        if covered != total_sectors:
            print("MISMATCH: the table covers %d sectors, the image has %d" % (covered, total_sectors))
            sys.exit(1)
        fd = os.open(args.device, os.O_RDONLY)
        segments = extents
    else:
        fd = os.open(args.file, os.O_RDONLY)
        segments = [(0, total_sectors, 0)]

    checked = 0
    for start, length, offset in segments:
        done = 0
        while done < length:
            if step == 1:
                n = min(CHUNK_SECTORS, length - done)
                data = os.pread(fd, n * SECTOR, (offset + done) * SECTOR)
                if len(data) != n * SECTOR:
                    print("MISMATCH: short read at logical sector %d" % (start + done))
                    sys.exit(1)
                for k in range(n):
                    idx = start + done + k
                    if data[k * SECTOR:k * SECTOR + 32] != header(idx, nonce):
                        print("MISMATCH at logical sector %d: found %s" %
                              (idx, data[k * SECTOR:k * SECTOR + 32].hex()))
                        sys.exit(1)
                checked += n
                done += n
            else:
                idx = start + done
                if idx % step == 0:
                    data = os.pread(fd, 32, (offset + done) * SECTOR)
                    if data != header(idx, nonce):
                        print("MISMATCH at logical sector %d: found %s" % (idx, data.hex()))
                        sys.exit(1)
                    checked += 1
                    done += 1
                else:
                    done += min(step - idx % step, length - done)
    print("OK: %d sectors checked (%s), all carry the expected index and nonce"
          % (checked, "every sector" if step == 1 else "1 of every %d" % step))


if __name__ == "__main__":
    main()
