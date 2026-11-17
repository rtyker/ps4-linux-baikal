#!/usr/bin/env python3
"""Stream a patterned disk-image file to stdout (meant for an FTP upload with `curl -T -`).

Every 512-byte sector starts with a 32-byte header:

    bytes  0..7   magic  b"PS4IMG01"
    bytes  8..15  little-endian 64-bit sector index (0-based, counted from the start of the image)
    bytes 16..31  16-byte nonce (random per image, printed to stderr unless --nonce is given)

The rest of the sector is zero. Reading a sector back through any block map and finding the right
index plus the right nonce proves that the map points at exactly the blocks of this file, in order.
A plain zero-filled image cannot prove that, because zeros look the same everywhere.

Usage:
    gen_pattern_image.py --size-gib 8 --nonce 00112233445566778899aabbccddeeff | curl -T - ftp://...
    gen_pattern_image.py --size-gib 8 --nonce ... --skip-bytes 1073741824 | curl -T - -a ftp://...   # resume

The size must be a whole number of MiB. The script writes nothing to disk.
"""
import argparse
import os
import struct
import sys

MAGIC = b"PS4IMG01"
SECTOR = 512
CHUNK_SECTORS = 2048            # 1 MiB per write
CHUNK_BYTES = CHUNK_SECTORS * SECTOR


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    size = ap.add_mutually_exclusive_group(required=True)
    size.add_argument("--size-gib", type=int, help="image size in GiB")
    size.add_argument("--size-mib", type=int, help="image size in MiB")
    ap.add_argument("--nonce", help="32 hex characters (16 bytes); random if omitted")
    ap.add_argument("--skip-bytes", type=int, default=0,
                    help="start streaming at this byte offset (resume an interrupted upload); "
                         "must be a multiple of 1 MiB")
    args = ap.parse_args()

    total = args.size_gib * 1024 ** 3 if args.size_gib is not None else args.size_mib * 1024 ** 2
    if total <= 0 or total % CHUNK_BYTES:
        sys.exit("ERROR: the size must be a positive whole number of MiB")
    if args.skip_bytes < 0 or args.skip_bytes % CHUNK_BYTES or args.skip_bytes >= total:
        sys.exit("ERROR: --skip-bytes must be a multiple of 1 MiB and smaller than the image size")

    if args.nonce:
        if len(args.nonce) != 32:
            sys.exit("ERROR: --nonce needs exactly 32 hex characters")
        nonce = bytes.fromhex(args.nonce)
    else:
        nonce = os.urandom(16)
    print("nonce=%s size_bytes=%d skip_bytes=%d" % (nonce.hex(), total, args.skip_bytes), file=sys.stderr)

    # Template chunk: magic and nonce are fixed; only the 8-byte index changes per sector.
    buf = bytearray(CHUNK_BYTES)
    for i in range(CHUNK_SECTORS):
        base = i * SECTOR
        buf[base:base + 8] = MAGIC
        buf[base + 16:base + 32] = nonce

    out = sys.stdout.buffer
    first_sector = args.skip_bytes // SECTOR
    end_sector = total // SECTOR
    while first_sector < end_sector:
        for i in range(CHUNK_SECTORS):
            struct.pack_into("<Q", buf, i * SECTOR + 8, first_sector + i)
        out.write(buf)
        first_sector += CHUNK_SECTORS
    out.flush()


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.exit(1)
