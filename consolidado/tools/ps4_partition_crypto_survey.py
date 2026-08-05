#!/usr/bin/env python3
"""
Levantamento de criptografia por partição do HD interno do PS4.

Motivação (2026-08-01): toda a investigação de decriptação até agora atacou
apenas sda13 (12G) e sda27 (897G) — justamente as duas partições grandes, que
segundo a psdevwiki usam chave derivada pelo SAMU (`sceSblWrapHddEapPartitionKeyData`)
e portanto NÃO são decriptáveis com a chave EAP flat.

As partições que a cena consegue decriptar com a `eap_hdd_key` são as pequenas
(`eap_vsh` ~512M, `eap_user`). Este script varre TODAS as partições, mede
entropia do texto cifrado e do texto decriptado sob vários tweaks, e procura
magics de filesystem — para descobrir onde a chave flat funciona e assim
calibrar a fórmula de tweak.

Sinal de busca: dado cifrado tem entropia ~7.99 bits/byte. Dado decriptado
corretamente (superbloco de FS) é estruturado — muitos zeros, entropia baixa.
Isso dá um GRADIENTE que a caça a magic específico não dá.

Uso (rodar no PS4, como root):
    python3 ps4_partition_crypto_survey.py --key /tmp/eap_hdd_key.bin
"""
import argparse
import math
import os
import struct
import sys

SECTOR = 512

MAGICS = [
    ("UFS2 superblock", bytes.fromhex("19540119")),
    ("UFS1 superblock", bytes.fromhex("00011954")),
    ("ext2/3/4", bytes.fromhex("53ef")),
    ("FAT boot sig", bytes.fromhex("55aa")),
    ("NTFS", b"NTFS    "),
    ("exFAT", b"EXFAT   "),
    ("PFS (proj. 0x1332A0B)", struct.pack("<I", 0x01332A0B)),
    ("PFS (proj. BE)", struct.pack(">I", 0x01332A0B)),
    ("GPT header", b"EFI PART"),
    ("SCE magic", b"\x7fCNT"),
]


def entropy(data: bytes) -> float:
    if not data:
        return 0.0
    hist = [0] * 256
    for b in data:
        hist[b] += 1
    n = len(data)
    e = 0.0
    for c in hist:
        if c:
            p = c / n
            e -= p * math.log2(p)
    return e


def zero_ratio(data: bytes) -> float:
    return data.count(0) / len(data) if data else 0.0


def find_magics(data: bytes):
    hits = []
    for name, sig in MAGICS:
        off = data.find(sig)
        if off >= 0:
            hits.append(f"{name}@0x{off:x}")
    return hits


def read_sectors(dev: str, lba: int, count: int) -> bytes:
    with open(dev, "rb") as f:
        f.seek(lba * SECTOR)
        return f.read(count * SECTOR)


def xts_decrypt(key: bytes, data: bytes, first_tweak: int) -> bytes:
    """Decripta data (múltiplo de 512) tratando cada setor como uma data unit XTS."""
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

    out = bytearray()
    for i in range(len(data) // SECTOR):
        tweak = (first_tweak + i).to_bytes(16, "little")
        dec = Cipher(algorithms.AES(key), modes.XTS(tweak)).decryptor()
        out += dec.update(data[i * SECTOR:(i + 1) * SECTOR])
    return bytes(out)


def partitions(disk_name: str):
    base = f"/sys/block/{disk_name}"
    parts = []
    for entry in sorted(os.listdir(base)):
        p = os.path.join(base, entry)
        if not entry.startswith(disk_name) or not os.path.isfile(os.path.join(p, "start")):
            continue
        with open(os.path.join(p, "start")) as f:
            start = int(f.read().strip())
        with open(os.path.join(p, "size")) as f:
            size = int(f.read().strip())
        parts.append((entry, start, size))
    parts.sort(key=lambda t: t[1])
    return parts


def human(sectors: int) -> str:
    b = sectors * SECTOR
    for unit in ("B", "K", "M", "G", "T"):
        if b < 1024 or unit == "T":
            return f"{b:.0f}{unit}" if unit == "B" else f"{b:.1f}{unit}"
        b /= 1024
    return f"{b:.1f}T"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--disk", default="sda")
    ap.add_argument("--key", required=True, help="eap_hdd_key.bin (32 bytes)")
    ap.add_argument("--sectors", type=int, default=8, help="setores lidos por partição")
    args = ap.parse_args()

    with open(args.key, "rb") as f:
        key = f.read()
    if len(key) != 32:
        sys.exit(f"chave deve ter 32 bytes, tem {len(key)}")

    dev = f"/dev/{args.disk}"
    parts = partitions(args.disk)

    print(f"# Levantamento de {dev} — {len(parts)} partições")
    print(f"# chave: {key.hex()[:16]}... ({len(key)} bytes)")
    print(f"# entropia ~7.99 = cifrado/aleatório · <7.5 = estruturado (SUSPEITO DE SUCESSO)")
    print()

    for name, start, size in parts:
        raw = read_sectors(dev, start, args.sectors)
        if not raw:
            print(f"{name}: (leitura falhou)")
            continue

        e_raw = entropy(raw)
        z_raw = zero_ratio(raw)
        m_raw = find_magics(raw)

        print(f"== {name}  start={start}  size={human(size)} ==")
        print(f"   RAW      entropia={e_raw:.3f} zeros={z_raw*100:5.1f}% "
              f"magics={m_raw if m_raw else '-'}")
        print(f"   RAW[:32] {raw[:32].hex()}")

        # candidatos de tweak: 0 (relativo), start (LBA absoluto), start*2 (o
        # valor que está no mapper vivo do sda27), e start em unidades de 4K
        candidates = [
            ("tweak=0 (relativo)", 0),
            ("tweak=start (absLBA)", start),
            ("tweak=start*2", start * 2),
            ("tweak=start/8 (4K)", start // 8),
        ]
        best = None
        for label, tw in candidates:
            try:
                pt = xts_decrypt(key, raw, tw)
            except Exception as exc:  # pragma: no cover
                print(f"   {label}: erro {exc}")
                continue
            e = entropy(pt)
            z = zero_ratio(pt)
            m = find_magics(pt)
            flag = "  <<< SUSPEITO" if (e < 7.5 or m) else ""
            print(f"   {label:22s} entropia={e:.3f} zeros={z*100:5.1f}% "
                  f"magics={m if m else '-'}{flag}")
            if best is None or e < best[0]:
                best = (e, label, pt)
        if best and best[0] < 7.5:
            print(f"   >>> melhor: {best[1]} — primeiros 64 bytes decriptados:")
            print(f"   {best[2][:64].hex()}")
        print()


if __name__ == "__main__":
    main()
