#!/usr/bin/env python3
"""List the segments and entries of an initramfs the way the kernel unpacks it.

The Linux initramfs unpacker (init/initramfs.c, unpack_to_rootfs) accepts a concatenation of cpio "newc"
archives, each either plain or compressed, with zero padding in between. A plain archive must start at a
4-byte aligned offset. This script follows the same loop, so it shows exactly what the kernel will extract.

Usage:
    list_initramfs_segments.py INITRAMFS                  # segments and a summary
    list_initramfs_segments.py INITRAMFS --all            # also list every entry
    list_initramfs_segments.py INITRAMFS --extract PATH   # write one file's content to stdout (last one wins)
    list_initramfs_segments.py INITRAMFS --find NAME      # list entries whose path ends with NAME

Only gzip compression is understood (the project's initramfs is gzip). It only reads; it never extracts to disk.
"""
import argparse
import sys
import zlib

HDR = 110


def parse_newc(data, base_offset=0):
    """Yield (name, mode, size, content) for each entry up to and including TRAILER!!!; return end offset."""
    off = 0
    entries = []
    while True:
        if data[off:off + 6] != b"070701":
            raise ValueError("bad newc magic at segment offset %d (absolute %d)" % (off, base_offset + off))
        f = [int(data[off + 6 + 8 * i:off + 14 + 8 * i], 16) for i in range(13)]
        mode, filesize, namesize = f[1], f[6], f[11]
        name = data[off + HDR:off + HDR + namesize - 1].decode("utf-8", "replace")
        start = (off + HDR + namesize + 3) & ~3
        content = data[start:start + filesize]
        off = (start + filesize + 3) & ~3
        if name == "TRAILER!!!":
            return entries, off
        entries.append((name, mode, filesize, content))


def walk(buf):
    """Mimic unpack_to_rootfs: return a list of segments (kind, absolute offset, length, entries)."""
    segments = []
    pos = 0
    while pos < len(buf):
        if buf[pos:pos + 1] == b"0" and pos % 4 == 0:
            entries, used = parse_newc(buf[pos:], pos)
            segments.append(("plain cpio", pos, used, entries))
            pos += used
        elif buf[pos] == 0:
            pos += 1
        elif buf[pos:pos + 2] == b"\x1f\x8b":
            d = zlib.decompressobj(16 + zlib.MAX_WBITS)
            raw = d.decompress(buf[pos:])
            used = len(buf) - pos - len(d.unused_data)
            entries, _ = parse_newc(raw)
            segments.append(("gzip cpio", pos, used, entries))
            pos += used
        else:
            raise ValueError("unrecognized data at offset %d: %s" % (pos, buf[pos:pos + 8].hex()))
    return segments


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("initramfs")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--extract")
    ap.add_argument("--find")
    args = ap.parse_args()

    with open(args.initramfs, "rb") as f:
        buf = f.read()
    segments = walk(buf)

    if args.extract:
        want = args.extract.lstrip("./")
        found = None
        for _, _, _, entries in segments:
            for name, mode, size, content in entries:
                if name.lstrip("./") == want:
                    found = content
        if found is None:
            sys.exit("not found: " + args.extract)
        sys.stdout.buffer.write(found)
        return

    print("file: %s (%d bytes)" % (args.initramfs, len(buf)))
    for n, (kind, off, used, entries) in enumerate(segments, 1):
        print("segment %d: %-10s offset %-10d length %-10d entries %d" % (n, kind, off, used, len(entries)))
        for name, mode, size, _ in entries:
            if args.all or (args.find and name.endswith(args.find)) or (n > 1 and kind == "plain cpio"):
                print("    %06o %10d  %s" % (mode, size, name))
    trailing = len(buf) - (segments[-1][1] + segments[-1][2]) if segments else 0
    print("bytes after the last segment (zero padding): %d" % trailing)


if __name__ == "__main__":
    main()
