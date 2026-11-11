#!/usr/bin/env python3
"""
ps4_cmtab_generator.py — Gera automaticamente o arquivo /etc/cryptmount/cmtab
ou comandos cryptsetup para montar todas as partições do HD do PS4 com os offsets LBA corretos.
"""

import sys
import os
import struct
import uuid

ORBIS_GUID_TABLE = {
    "76a9a5b4-44b0-472a-bde3-3107472adee2": ("sda13", "ps4_system"),
    "c638477a-e002-4b57-a454-a27fb63a33a8": ("sda27", "ps4_user")
}

def generate_cmtab(device_path="/dev/sda", key_file="/etc/ps4_keys.bin"):
    if not os.path.exists(device_path):
        print(f"# Aviso: Dispositivo {device_path} não encontrado localmente. Gerando modelo genérico.")
        print("# Exemplo de cmtab para cryptmount:\n")
        print("ps4_system {")
        print("    dev=/dev/sda13")
        print("    flags=readonly")
        print("    dir=/mnt/ps4_system")
        print("    fstype=ufs2")
        print("    cipher=aes-xts-plain64")
        print(f"    keyfile={key_file}")
        print("    keyformat=raw")
        print("    keylen=256")
        print("    ivoffset=19398656")
        print("}\n")
        print("ps4_user {")
        print("    dev=/dev/sda27")
        print("    flags=readonly")
        print("    dir=/mnt/ps4_user")
        print("    fstype=ufs2")
        print("    cipher=aes-xts-plain64")
        print(f"    keyfile={key_file}")
        print("    keyformat=raw")
        print("    keylen=256")
        print("    ivoffset=67108864")
        print("}")
        return

    with open(device_path, "rb") as f:
        f.seek(1024)
        gpt_entries = f.read(128 * 32)

    print("# /etc/cryptmount/cmtab para HD do PS4")
    print("# Gerado automaticamente por ps4_cmtab_generator.py\n")

    for idx in range(32):
        entry = gpt_entries[idx*128 : (idx+1)*128]
        type_guid_raw = entry[0:16]
        if type_guid_raw == b'\x00' * 16:
            continue

        type_guid = str(uuid.UUID(bytes_le=type_guid_raw)).lower()
        start_lba = struct.unpack_from('<Q', entry, 32)[0]
        part_num = idx + 1

        if type_guid in ORBIS_GUID_TABLE:
            part_code, name = ORBIS_GUID_TABLE[type_guid]
            print(f"{name} {{")
            print(f"    dev=/dev/sda{part_num}")
            print(f"    flags=readonly")
            print(f"    dir=/mnt/{name}")
            print(f"    fstype=ufs2")
            print(f"    cipher=aes-xts-plain64")
            print(f"    keyfile={key_file}")
            print(f"    keyformat=raw")
            print(f"    keylen=256")
            print(f"    ivoffset={start_lba}")
            print("}\n")

if __name__ == "__main__":
    dev = sys.argv[1] if len(sys.argv) > 1 else "/dev/sda"
    key = sys.argv[2] if len(sys.argv) > 2 else "/etc/ps4_keys.bin"
    generate_cmtab(dev, key)
