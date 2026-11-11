#!/usr/bin/env python3
"""
ps4_eap_key_extractor.py — Extrai a chave ERK/RIV (SCE_EAP_HDD__KEY) de um dump NOR/sflash0 ou dump de memória Orbis.
"""

import sys
import os
import struct

def extract_key(dump_path, output_key_path="/tmp/ps4_keys.bin"):
    if not os.path.exists(dump_path):
        print(f"Erro: arquivo {dump_path} não encontrado.")
        return False

    with open(dump_path, "rb") as f:
        data = f.read()

    target_label = b"SCE_EAP_HDD__KEY"
    pos = data.find(target_label)

    if pos != -1 and pos >= 64:
        key_pos = pos - 64
        erk = data[key_pos:key_pos+32]
        riv = data[key_pos+32:key_pos+64]
        
        print(f"SCE_EAP_HDD__KEY encontrado no offset 0x{key_pos:x}!")
        print(f"  ERK (32 bytes): {erk.hex()}")
        print(f"  RIV (32 bytes): {riv.hex()}")
        
        os.makedirs(os.path.dirname(output_key_path), exist_ok=True)
        with open(output_key_path, "wb") as out:
            out.write(erk)
        print(f"Chave ERK (32 bytes) salva em {output_key_path}")
        return True
    else:
        print("Label SCE_EAP_HDD__KEY não encontrada ou offset inválido.")
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Uso: {sys.argv[0]} <caminho_do_dump> [saida_chave.bin]")
        sys.exit(1)
    dump_file = sys.argv[1]
    out_file = sys.argv[2] if len(sys.argv) > 2 else "/tmp/ps4_keys.bin"
    extract_key(dump_file, out_file)
