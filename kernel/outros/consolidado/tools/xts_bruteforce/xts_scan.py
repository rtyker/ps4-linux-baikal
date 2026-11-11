#!/usr/bin/env python3
"""Local validation of PS4 HDD XTS decryption candidates - scans all sectors."""
import sys
from Crypto.Cipher import AES

ERK = bytes.fromhex("7fcf0536d3b5f5bd09a5d7b3833f868bbe1f6d90803b4f54029e6265f6476af6")
PROD = bytes.fromhex("e4090248c0aaa615eb00c761f6d1f1a83564c1f52883c9b47d63b58970d911c7")

def rev16(k):
    return k[:16][::-1] + k[16:][::-1]

def revall(k):
    return k[::-1]

def xts_decrypt_block(key, tweak, data):
    try:
        c = AES.new(key, AES.MODE_XTS)
        return c.decrypt(data, segment_number=tweak)
    except Exception:
        return None

PFS = (0x1332A0B).to_bytes(4, "little")
UFS2 = (0x19540119).to_bytes(4, "little")
UFS2_BE = (0x19540119).to_bytes(4, "big")
# PS4 PFS superblock also has magic 0x1332A0B stored big-endian? check both
PFS_BE = (0x1332A0B).to_bytes(4, "big")

def scan_sectors(buf):
    """Return list of (magic_name, sector, byte_off) for magic found anywhere."""
    hits = []
    nsec = len(buf) // 512
    for si in range(nsec):
        sec = buf[si*512:(si+1)*512]
        for name, mag in (("PFS", PFS), ("PFSbe", PFS_BE), ("UFS2", UFS2), ("UFS2be", UFS2_BE)):
            off = sec.find(mag)
            if off != -1:
                hits.append((name, si, off))
    return hits

def main():
    target = sys.argv[1]
    data = open(target, "rb").read()
    nsec = len(data) // 512
    print(f"File: {target}, {nsec} sectors")

    keys = {
        "ERK": ERK, "ERK-r16": rev16(ERK), "ERK-ra": revall(ERK),
        "PROD": PROD, "PROD-r16": rev16(PROD), "PROD-ra": revall(PROD),
    }
    tweaks = {
        "0": 0,
        "absLBA-57147392": 57147392,
        "ivofs-218103808": 218103808,
    }
    total = 0
    for kn, k in keys.items():
        for variant, kk in (("as-is", k), ("swap", k[16:] + k[:16])):
            for tn, tw in tweaks.items():
                total += 1
                for si in range(nsec):
                    sec = data[si*512:(si+1)*512]
                    p = xts_decrypt_block(kk, tw, sec)
                    if p is None:
                        break
                    for name, mag in (("PFS", PFS), ("PFSbe", PFS_BE), ("UFS2", UFS2), ("UFS2be", UFS2_BE)):
                        off = p.find(mag)
                        if off != -1:
                            print(f"[HIT] {kn}/{variant} tweak={tn} ({tw}) sector={si} magic={name} byteoff={off}")
                            print("   first 32 dec:", p[:32].hex())
                            sys.exit(0)
    print(f"done, {total} combos x {nsec} sectors scanned, no hit")

if __name__ == "__main__":
    main()
