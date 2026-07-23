#!/usr/bin/env python3
"""
compare_bits.py — Utilitário de Comparação Bit a Bit para Registradores do PS4 (SQLite)

Recursos:
 1. Compara 2 valores hexadecimais de 32 bits bit a bit.
 2. Exibe diagrama binário formatado com índice de cada bit (0 a 31).
 3. Destaca bits alterados (0 -> 1 ou 1 -> 0), mantidos em HIGH ou LOW.
 4. Calcula Máscara XOR (Diferenças), Bitwise AND e Bitwise OR.
 5. Permite consultar registradores gravados direto no SQLite ps4_hardware_memory.db.

Uso:
    python3 compare_bits.py 0x000016c9 0x000016d9
    python3 compare_bits.py --reg BAR2_CLOCK_PULSE
"""

import sys
import argparse
import sqlite3
import re

DB_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db"

def hex_to_int(val_str):
    clean = val_str.strip()
    match = re.search(r'0x[0-9a-fA-F]+|\b[0-9a-fA-F]{8}\b', clean)
    if match:
        return int(match.group(0), 16) if match.group(0).startswith("0x") else int(match.group(0), 16)
    return int(clean, 16)

def format_bits(val, label):
    b_str = f"{val:032b}"
    formatted = " ".join([b_str[i:i+4] for i in range(0, 32, 4)])
    print(f"{label:18s}: 0x{val:08x}  ->  [ {formatted} ]")
    return b_str

def compare_values(val1_int, val2_int, name1="Valor 1", name2="Valor 2"):
    print("=" * 75)
    print(f"COMPARAÇÃO BIT A BIT: {name1} vs {name2}")
    print("=" * 75)

    b1 = format_bits(val1_int, name1)
    b2 = format_bits(val2_int, name2)

    xor_mask = val1_int ^ val2_int
    and_mask = val1_int & val2_int
    or_mask  = val1_int | val2_int

    print("-" * 75)
    format_bits(xor_mask, "MÁSCARA XOR (DIFF)")
    format_bits(and_mask, "BITWISE AND")
    format_bits(or_mask,  "BITWISE OR")

    print("-" * 75)
    print("DETALHAMENTO DOS BITS ALTERADOS:")
    
    diff_count = 0
    for bit in range(32):
        bit_val1 = (val1_int >> bit) & 1
        bit_val2 = (val2_int >> bit) & 1
        if bit_val1 != bit_val2:
            diff_count += 1
            print(f"  ⚡ Bit {bit:2d} (Máscara 0x{1<<bit:08x}): {bit_val1}  ==>  {bit_val2}  ({'ATIVADO (0->1)' if bit_val2 > bit_val1 else 'DESATIVADO (1->0)'})")

    if diff_count == 0:
        print("  ✅ Nenhum bit alterado (Valores idênticos).")
    else:
        print(f"\nTotal de bits alterados: {diff_count}")
    print("=" * 75)

def get_register_from_db(reg_name):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT reg_name, base_bar, reg_offset, description FROM hardware_registers WHERE reg_name = ?;", (reg_name,))
    row = cursor.fetchone()
    conn.close()
    return row

def main():
    parser = argparse.ArgumentParser(description="Comparador bit a bit de registradores PS4")
    parser.add_argument("val1", nargs="?", help="Primeiro valor hex (ex: 0x000016c9)")
    parser.add_argument("val2", nargs="?", help="Segundo valor hex (ex: 0x000016d9)")
    parser.add_argument("--reg", help="Nome do registrador no SQLite para consultar valor")

    args = parser.parse_args()

    if args.reg:
        row = get_register_from_db(args.reg)
        if not row:
            print(f"ERRO: Registrador '{args.reg}' não encontrado no SQLite.")
            sys.exit(1)
        name, bar, offset, desc = row
        print(f"REGISTRADOR ENCONTRADO NO SQLITE: {name} ({bar} + {offset})")
        print(f"Descrição: {desc}")
        hex_match = re.search(r'0x[0-9a-fA-F]{8}', desc)
        if hex_match:
            v_int = int(hex_match.group(0), 16)
            format_bits(v_int, name)
        sys.exit(0)

    if not args.val1 or not args.val2:
        # Exemplo padrão de demonstração se nenhum argumento for fornecido
        v1 = 0x000016c9  # BAR2 Clock Pulse Padrão
        v2 = 0x000016d9  # BAR2 Clock Pulse com bit GbE ativado
        compare_values(v1, v2, "BAR2_CLOCK (0x16c9)", "BAR2_PULSE (0x16d9)")
        sys.exit(0)

    v1_int = hex_to_int(args.val1)
    v2_int = hex_to_int(args.val2)
    compare_values(v1_int, v2_int, f"0x{v1_int:08x}", f"0x{v2_int:08x}")

if __name__ == "__main__":
    main()
