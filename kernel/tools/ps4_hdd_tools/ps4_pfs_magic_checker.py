#!/usr/bin/env python3
"""
ps4_pfs_magic_checker.py — Verifica o magic number UFS2 / PFS (0x1332A0B) em um dispositivo decriptado (/dev/mapper/ps4_sdaX).
"""

import sys
import os
import struct

UFS2_MAGIC = 0x1332A0B
PFS_OFFSETS = [0, 8192, 65536, 131072]

def check_pfs_magic(mapper_path):
    if not os.path.exists(mapper_path):
        print(f"Erro: dispositivo {mapper_path} não encontrado.")
        return False

    with open(mapper_path, "rb") as f:
        print(f"=== Checagem de Magic PFS/UFS2 em {mapper_path} ===")
        for offset in PFS_OFFSETS:
            try:
                f.seek(offset)
                data = f.read(512)
                if len(data) < 512:
                    continue
                # Test 32-bit integers at common superblock offsets (e.g. 0x0, 0x4, 0x8, 0x54, 0x5c, 0x100)
                for i in range(0, 512 - 4, 4):
                    val = struct.unpack_from('<I', data, i)[0]
                    val_be = struct.unpack_from('>I', data, i)[0]
                    if val == UFS2_MAGIC or val_be == UFS2_MAGIC:
                        print(f"  [SUCESSO] Magic UFS2/PFS (0x1332A0B) ENCONTRADO!")
                        print(f"    Offset da busca: {offset} bytes")
                        print(f"    Offset relativo ao superbloco: 0x{i:x}")
                        print(f"    Endianness: {'Little Endian' if val == UFS2_MAGIC else 'Big Endian'}")
                        return True
            except Exception as e:
                pass

        # Print first 16 bytes snippet
        f.seek(0)
        head = f.read(16).hex()
        print(f"  [FALHA] Magic UFS2 (0x1332A0B) não encontrado nos primeiros blocos.")
        print(f"  Primeiros 16 bytes crus do mapper: {head}")
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Uso: {sys.argv[0]} /dev/mapper/ps4_sda13")
        sys.exit(1)
    check_pfs_magic(sys.argv[1])
