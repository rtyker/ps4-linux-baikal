#!/usr/bin/env python3
"""Local validation of PS4 HDD XTS decryption candidates - scans all sectors."""
import sys
from Crypto.Cipher import AES

# Chaves refutadas (não decifram as partições). NÃO ficam versionadas: carregue do
# ambiente, ex.:  set -a; . .env.keys; set +a   ou  export ERK=<hex> PROD=<hex>
import os
ERK = bytes.fromhex(os.environ.get("ERK_HDD_KEY", "")) if os.environ.get("ERK_HDD_KEY") else None
PROD = bytes.fromhex(os.environ.get("PROD_HDD_KEY", "")) if os.environ.get("PROD_HDD_KEY") else None
if ERK is None or PROD is None:
    raise SystemExit("Defina ERK_HDD_KEY e PROD_HDD_KEY (hex) no ambiente — ver ~/ps4-keys/chaves-refutadas.txt")

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
