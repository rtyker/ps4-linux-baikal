#!/usr/bin/env python3
"""
ps4_pfs_magic_checker.py — Valida se um dispositivo já decifrado contém o
superbloco UFS2 do PS4.

Correção de 2026-11-13: o magic correto é **0x19540119** (UFS2), localizado em
0x1055C (= SBLOCK_UFS2 65536 + fs_magic 1372), em little-endian. A versão antiga
deste script procurava 0x1332A0B (valor errado, mascarado como "PFS/UFS2") e por
isso dava falso negativo mesmo com o mapper correto.

Uso:
    python3 ps4_pfs_magic_checker.py /dev/mapper/ps4_sda27
"""

import sys
import os

UFS2_MAGIC = 0x19540119
# SBLOCK_UFS2 = 65536; fs_magic fica no offset 1372 dentro de struct fs
UFS2_MAGIC_OFFSET = 0x10000 + 1372  # 0x1055C
# UFS1 (SBLOCK_UFS1 = 8192) — só para diagnóstico
UFS1_MAGIC_OFFSET = 0x2000 + 1372


def check_ufs_magic(path: str) -> bool:
    if not os.path.exists(path):
        print(f"Erro: dispositivo {path} não encontrado.")
        return False

    with open(path, "rb") as f:
        print(f"=== Checagem de magic UFS2 em {path} ===")

        f.seek(UFS2_MAGIC_OFFSET)
        raw = f.read(4)
        val = int.from_bytes(raw, "little")
        if val == UFS2_MAGIC:
            print(f"  [OK] Magic UFS2 0x{UFS2_MAGIC:08X} encontrado em 0x{UFS2_MAGIC_OFFSET:X}.")
            return True

        f.seek(UFS1_MAGIC_OFFSET)
        raw1 = f.read(4)
        val1 = int.from_bytes(raw1, "little")
        if val1 == UFS2_MAGIC:
            print(f"  [OK] Magic encontrado em 0x{UFS1_MAGIC_OFFSET:X} — parece UFS1, não UFS2.")
            print("       Use ufstype=ufs1 no mount (o PS4 usa ufs2 na partição user).")
            return True

        print(f"  [FALHA] 0x{UFS2_MAGIC:08X} não encontrado em 0x{UFS2_MAGIC_OFFSET:X}.")
        print(f"          lido: 0x{val:08X} (bytes {raw.hex() or 'vazio'})")
        f.seek(0)
        head = f.read(16)
        print(f"  Primeiros 16 bytes: {head.hex()}")
        # Assinatura FAT: EB ?? 90 (x86 jump) ou EB ?? ?? — partições update são FAT32.
        if len(head) >= 3 and head[0] == 0xEB and head[2] == 0x90:
            print("  Isto parece um volume FAT/FAT32 (ex.: sda25 update) — não é UFS, está correto.")
            return False
        print("  Causa provável: iv_offset errado no mapper (deve ser (dev_no-1)<<32)")
        print("  ou partição que usa a chave SAMU/versioned (sda9-12/19/31) / não é FS (sda13).")
        return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Uso: {sys.argv[0]} /dev/mapper/ps4_sda27")
        sys.exit(1)
    sys.exit(0 if check_ufs_magic(sys.argv[1]) else 1)
