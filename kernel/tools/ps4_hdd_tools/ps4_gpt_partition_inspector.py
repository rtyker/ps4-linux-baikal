#!/usr/bin/env python3
"""
ps4_gpt_partition_inspector.py — Inspeciona as entradas GPT de um HD do PS4 (/dev/sda ou imagem de disco),
compara os GUIDs com a tabela oficial de 16 GUIDs do kernel Orbis e exibe os offsets LBA absolutos para decriptação.
"""

import sys
import os
import struct
import uuid

# Tabela oficial de 16 Type-GUIDs extraída de memoriateste.bin (0x1a6d800)
ORBIS_GUID_TABLE = [
    ("0",  "eabbf00b-c299-4488-9de9-b2839bce7546", "Partição 00 (Sistema/Boot)"),
    ("1",  "17800f17-b9e1-425d-b937-0119a0813172", "Partição 01 (Swap/Temp)"),
    ("2",  "ccb52e94-ebef-48c4-a195-9e2da5b0292c", "Partição 02 (Kernel/Recovery)"),
    ("3",  "145268bf-63ad-47c1-9378-9aacd9beed7c", "Partição 03 (System Auxiliary)"),
    ("4",  "6e0c5310-8445-4066-b571-9b65fdb75935", "Partição 04 (System Data)"),
    ("5",  "dc85025f-a694-4109-be44-fa0c063e8b81", "Partição 05 (System Update)"),
    ("6",  "76a9a5b4-44b0-472a-bde3-3107472adee2", "Partição 13 (System / sda13)"),
    ("7",  "b2555aed-b639-4382-9562-3a2929b616f9", "Partição 07 (User Settings)"),
    ("8",  "80dd49e3-a985-4887-81de-1daca47aed90", "Partição 08 (App DB)"),
    ("9",  "a71ff62d-1421-4dd9-935d-25dabd81bec5", "Partição 09 (Local Cache)"),
    ("10", "42e3afc3-b58d-4379-9f86-c01765fcb032", "Partição 10 (Download Cache)"),
    ("11", "db1652f2-b2df-4274-b6e7-84c71d954cbb", "Partição 11 (Game Saves Base)"),
    ("12", "fdb5ede1-73c3-4c43-8c5b-2d3dcfcddff8", "Partição 12 (Trophy Data)"),
    ("13", "c638477a-e002-4b57-a454-a27fb63a33a8", "Partição 27 (Games User Data / sda27)"),
    ("14", "21e4dfb4-0040-4934-a037-ea9dc058eea6", "Partição 14 (Media Content)"),
    ("15", "3ef7290a-de81-4887-a11f-46fba765c71c", "Partição 15 (Reserved/Extended)")
]

GUID_MAP = {g[1].lower(): g for g in ORBIS_GUID_TABLE}

def inspect_gpt(device_path):
    if not os.path.exists(device_path):
        print(f"Erro: dispositivo {device_path} não encontrado.")
        return

    with open(device_path, "rb") as f:
        # Ir para o setor LBA 2 (byte 1024) onde a tabela de partições GPT começa
        f.seek(1024)
        gpt_entries = f.read(128 * 32) # Ler até 32 entradas

    print(f"=== Inspeção da Tabela GPT do PS4 em {device_path} ===")
    print(f"{'Partição':<10} {'Start LBA':<12} {'End LBA':<12} {'Orbis Index':<12} {'GUID Match / Descrição'}")
    print("-" * 75)

    for idx in range(32):
        entry = gpt_entries[idx*128 : (idx+1)*128]
        type_guid_raw = entry[0:16]
        if type_guid_raw == b'\x00' * 16:
            continue

        type_guid = str(uuid.UUID(bytes_le=type_guid_raw)).lower()
        start_lba = struct.unpack_from('<Q', entry, 32)[0]
        end_lba = struct.unpack_from('<Q', entry, 40)[0]
        part_num = idx + 1

        match_info = GUID_MAP.get(type_guid, ("-", type_guid, "Desconhecido"))
        orbis_idx = match_info[0]
        desc = match_info[2]

        print(f"sda{part_num:<7} {start_lba:<12} {end_lba:<12} {orbis_idx:<12} {desc}")

if __name__ == "__main__":
    dev = sys.argv[1] if len(sys.argv) > 1 else "/dev/sda"
    inspect_gpt(dev)
