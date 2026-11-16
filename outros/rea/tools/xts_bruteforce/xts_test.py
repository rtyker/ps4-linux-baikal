#!/usr/bin/env python3
"""Local validation of PS4 HDD XTS decryption candidates."""
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
    """Decrypt one 512-byte sector with XTS-AES. key=32B, tweak=int sector number."""
    try:
        c = AES.new(key, AES.MODE_XTS)
        return c.decrypt(data, segment_number=tweak)
    except Exception as e:
        return None

PFS_MAGIC_LE = (0x1332A0B).to_bytes(4, "little")   # 0b 2a 33 01
UFS2_MAGIC_LE = (0x19540119).to_bytes(4, "little")  # FreeBSD UFS2

def scan(buf, name):
    hits = []
    for off in range(0, len(buf) - 512 + 1, 512):
        sec = buf[off:off+512]
        if PFS_MAGIC_LE in sec:
            hits.append(f"PFS magic at sector {off//512}, off {off}")
            break
        if UFS2_MAGIC_LE in sec:
            hits.append(f"UFS2 magic at sector {off//512}, off {off}")
            break
    return hits

def main():
    target = sys.argv[1]  # path to raw head file
    data = open(target, "rb").read()
    nsec = len(data) // 512
    print(f"File: {target}, {len(data)} bytes, {nsec} sectors")

    keys = {
        "ERK-raw": ERK,
        "ERK-rev16": rev16(ERK),
        "ERK-revall": revall(ERK),
        "PROD-raw": PROD,
        "PROD-rev16": rev16(PROD),
        "PROD-revall": revall(PROD),
    }
    tweaks = {
        "tweak0": 0,
        "absLBA(sda27=57147392)": 57147392,
        "ivoffset(N-1)<<23=218103808": 218103808,
    }
    # also try key halves swapped
    for kn, k in keys.items():
        for variant, kk in (("as-is", k), ("halves-swapped", k[16:] + k[:16])):
            for tn, tw in tweaks.items():
                p = xts_decrypt_block(kk, tw, data[:512])
                if p is None:
                    continue
                hits = scan(p, f"{kn}/{variant}/{tn}")
                if hits:
                    print(f"[HIT] key={kn} {variant} tweak={tn} ({tw}): {hits}")
                    # print decrypted first 32 bytes
                    print("   dec: ", p[:32].hex())
                # also scan a few more sectors for UFS2 superblock patterns
    print("done")

if __name__ == "__main__":
    main()
