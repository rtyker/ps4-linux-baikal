#!/usr/bin/env python3
"""SHA-256 of the first N bytes of a device or file, optionally ignoring the blocks of the image file.

Use it to show that the rest of the Orbis partition did not change while the image file was written through
a dm-linear map: take the hash before and after, passing the same --exclude-table. Sectors that belong to the
image (the *physical* ranges listed in the table) are replaced by zeros before hashing, so the legitimate
writes into the image do not disturb the result.

    region_hash.py --device /dev/mapper/ps4_sda27 --bytes 1073741824 --exclude-table rootfs.table

The script only reads.
"""
import argparse
import bisect
import hashlib
import os
import sys

SECTOR = 512


def load_ranges(path):
    ranges = []
    with open(path) as f:
        for n, line in enumerate(f, 1):
            parts = line.split()
            if not parts:
                continue
            if len(parts) != 5 or parts[2] != "linear":
                sys.exit("ERROR: table line %d is not a dm-linear line" % n)
            start = int(parts[4]) * SECTOR
            ranges.append((start, start + int(parts[1]) * SECTOR))
    ranges.sort()
    for a, b in zip(ranges, ranges[1:]):
        if a[1] > b[0]:
            sys.exit("ERROR: the table maps overlapping physical ranges; refusing to continue")
    return ranges


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--device", required=True)
    ap.add_argument("--bytes", type=int, required=True, help="how many bytes from the start to hash")
    ap.add_argument("--exclude-table", help="dm-linear table whose physical ranges are zeroed before hashing")
    ap.add_argument("--chunk-mib", type=int, default=4)
    args = ap.parse_args()

    ranges = load_ranges(args.exclude_table) if args.exclude_table else []
    starts = [r[0] for r in ranges]
    chunk = args.chunk_mib * 1024 * 1024
    h = hashlib.sha256()
    fd = os.open(args.device, os.O_RDONLY)
    off = 0
    zeroed = 0
    while off < args.bytes:
        n = min(chunk, args.bytes - off)
        data = bytearray(os.pread(fd, n, off))
        if len(data) != n:
            sys.exit("ERROR: short read at offset %d" % off)
        i = max(0, bisect.bisect_right(starts, off) - 1)
        while i < len(ranges) and ranges[i][0] < off + n:
            lo = max(ranges[i][0], off)
            hi = min(ranges[i][1], off + n)
            if lo < hi:
                data[lo - off:hi - off] = bytes(hi - lo)
                zeroed += hi - lo
            i += 1
        h.update(data)
        off += n
    print("%s  bytes=%d  excluded_bytes=%d" % (h.hexdigest(), args.bytes, zeroed))


if __name__ == "__main__":
    main()
