#!/usr/bin/env python3
"""Append a small cpio fragment (drive key, block-map table, metadata) to a copy of an initramfs.

The kernel unpacks concatenated archives, so the fragment simply follows the original initramfs, after zero
padding that puts it on a 4096-byte boundary. The fragment creates:

    /key/eap_hdd_key.bin        mode 0400   the 32-byte console key (never printed, never logged)
    /etc/ps4root/rootfs.table   mode 0444   the dm-linear table for the image file
    /etc/ps4root/meta           mode 0444   key=value lines describing the image

SECURITY: the output contains the console's drive key. It is refused if it would be written inside a git
working tree, and it is created with mode 0600. Keep it in a temporary folder, upload it, then delete it.
Never store it in distro/boot_referencia/, never commit it, never copy it to the USB drive.

Usage:
    append_boot_fragment.py --initramfs initramfs.cpio.gz --out /tmp/work/initramfs.cpio.gz \\
        --key ~/ps4-keys/eap_hdd_key.bin --table rootfs.table --meta rootfs.meta
"""
import argparse
import os
import sys
import time

HDR = 110


def newc(name, mode, data, ino, nlink=1):
    nm = name.encode() + b"\0"
    fields = [ino, mode, 0, 0, nlink, int(time.time()), len(data), 0, 0, 0, 0, len(nm), 0]
    hdr = b"070701" + b"".join(b"%08X" % v for v in fields)
    out = hdr + nm
    out += b"\0" * ((4 - len(out) % 4) % 4)
    out += data
    out += b"\0" * ((4 - len(data) % 4) % 4)
    return out


def inside_git_tree(path):
    d = os.path.dirname(os.path.realpath(path))
    while True:
        if os.path.exists(os.path.join(d, ".git")):
            return True
        parent = os.path.dirname(d)
        if parent == d:
            return False
        d = parent


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--initramfs", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--key", required=True, help="raw 32-byte key file")
    ap.add_argument("--table", required=True)
    ap.add_argument("--meta", required=True)
    args = ap.parse_args()

    if inside_git_tree(args.out):
        sys.exit("ERROR: refusing to write a key-bearing file inside a git working tree: " + args.out)
    if os.path.realpath(args.out) == os.path.realpath(args.initramfs):
        sys.exit("ERROR: --out must not be the input file")

    key = open(args.key, "rb").read()
    if len(key) != 32:
        sys.exit("ERROR: the key file must be exactly 32 raw bytes (got %d)" % len(key))
    table = open(args.table, "rb").read()
    meta = open(args.meta, "rb").read()
    base = open(args.initramfs, "rb").read()
    if base[:6] != b"070701" and base[:2] != b"\x1f\x8b":
        sys.exit("ERROR: the input does not look like an initramfs (unknown magic)")

    frag = b""
    frag += newc("key", 0o040700, b"", 1, 2)
    frag += newc("key/eap_hdd_key.bin", 0o100400, key, 2)
    frag += newc("etc", 0o040755, b"", 3, 2)
    frag += newc("etc/ps4root", 0o040755, b"", 4, 2)
    frag += newc("etc/ps4root/rootfs.table", 0o100444, table, 5)
    frag += newc("etc/ps4root/meta", 0o100444, meta, 6)
    frag += newc("TRAILER!!!", 0, b"", 0, 1)

    pad = (-len(base)) % 4096
    fd = os.open(args.out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(base)
        f.write(b"\0" * pad)
        f.write(frag)
        f.write(b"\0" * ((-f.tell()) % 4096))
    print("wrote %s: original %d bytes + %d bytes of padding + fragment %d bytes (fragment starts at %d)"
          % (args.out, len(base), pad, len(frag), len(base) + pad))


if __name__ == "__main__":
    main()
