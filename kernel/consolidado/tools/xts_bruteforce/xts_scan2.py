#!/usr/bin/env python3
"""Expanded PS4 HDD XTS validation: byte-reversed keys + ivoffset formula + sector sizes."""
import sys
from Crypto.Cipher import AES

ERK = bytes.fromhex("7fcf0536d3b5f5bd09a5d7b3833f868bbe1f6d90803b4f54029e6265f6476af6")
PROD = bytes.fromhex("e4090248c0aaa615eb00c761f6d1f1a83564c1f52883c9b47d63b58970d911c7")

def rev16(k): return k[:16][::-1] + k[16:][::-1]
def revall(k): return k[::-1]

PFS = (0x1332A0B).to_bytes(4, "little")
PFS_BE = (0x1332A0B).to_bytes(4, "big")
UFS2 = (0x19540119).to_bytes(4, "little")

def xts_decrypt(key, tweak, data):
    try:
        return AES.new(key, AES.MODE_XTS).decrypt(data, segment_number=tweak)
    except Exception:
        return None

def main():
    target = sys.argv[1]
    data = open(target, "rb").read()
    nsec512 = len(data) // 512
    print(f"File: {target}, {len(data)} bytes, {nsec512} sectors(512)")

    keys = {
        "ERK": ERK, "ERK-r16": rev16(ERK), "ERK-ra": revall(ERK),
        "PROD": PROD, "PROD-r16": rev16(PROD), "PROD-ra": revall(PROD),
    }
    # tweak candidates (sector numbers in 512-byte units), for first 512B sector
    tweaks = {
        "t0": 0,
        "absLBA57147392": 57147392,
        "ivofs218103808": 218103808,          # (27-1)<<32 / 512
        "ivofs+absLBA": 218103808 + 57147392,
        "ivofs*2": 436207616,
        "ivofs*2+abs": 436207616 + 57147392,
        "partoff_4096units_7143424": 7143424, # absLBA/8
        "ivofs4096_27262976": 27262976,       # (27-1)<<32 / 4096
    }

    def scan(buf512):
        hits = []
        for name, mag in (("PFS", PFS), ("PFSbe", PFS_BE), ("UFS2", UFS2)):
            off = buf512.find(mag)
            if off != -1:
                hits.append((name, off))
        return hits

    checked = 0
    for kn, k in keys.items():
        for variant, kk in (("as-is", k), ("swap", k[16:] + k[:16])):
            for tn, tw in tweaks.items():
                checked += 1
                # scan first 4096 sectors with this tweak (sector 0..4095, tweak=tw+sector)
                for si in range(min(4096, nsec512)):
                    sec = data[si*512:(si+1)*512]
                    p = xts_decrypt(kk, tw + si, sec)
                    if p is None:
                        break
                    for name, mag in (("PFS", PFS), ("PFSbe", PFS_BE), ("UFS2", UFS2)):
                        off = p.find(mag)
                        if off != -1:
                            print(f"[HIT] {kn}/{variant} tweak={tn}({tw})+sector{si} magic={name} byteoff={off}")
                            print("  dec[0:32]:", p[:32].hex())
                            sys.exit(0)
    print(f"done: {checked} key/tweak combos x first 4096 sectors, no hit")

if __name__ == "__main__":
    main()
