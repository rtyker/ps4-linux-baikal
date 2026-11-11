#!/usr/bin/env python3
"""
log_test.py — Helper CLI para registrar rapidamente novos testes no banco SQLite oficial.

Exemplo de uso:
  python3 log_test.py --phase "Fase 6" --name "Teste BAR2 Pulse" --target "GbE" --action "Escrita BAR2+0x10a030" --status "OK" --info "ChipID mudou para 0xb3"
"""

import os
import sqlite3
import argparse
import datetime

# Raiz da frente 1 (kernel/), derivada da localizacao do arquivo —
# substitui os caminhos absolutos antigos (/mnt/t/downloads/...).
_KERNEL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DB_PATH = _KERNEL + "/consolidado/ps4_hardware_memory.db"

def main():
    parser = argparse.ArgumentParser(description="Registra um novo teste no banco de dados SQLite oficial.")
    parser.add_argument("--phase", required=True, help="Ex: Fase 5, Fase 6")
    parser.add_argument("--name", required=True, help="Nome do teste")
    parser.add_argument("--target", required=True, help="Componente alvo (ex: GbE, SATA, PCI Config)")
    parser.add_argument("--action", required=True, help="Ação executada")
    parser.add_argument("--status", required=True, choices=["OK", "FAIL_PANIC", "FAIL_COLLATERAL", "REFUTED", "PENDING"], help="Status do teste")
    parser.add_argument("--info", required=True, help="Informação complementar / resultado")

    args = parser.parse_args()
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("""
    INSERT INTO test_history (timestamp, phase, test_name, target_component, action_taken, status, complementary_info)
    VALUES (?, ?, ?, ?, ?, ?, ?);
    """, (ts, args.phase, args.name, args.target, args.action, args.status, args.info))

    conn.commit()
    conn.close()
    print(f"✅ Teste '{args.name}' registrado com sucesso no banco SQLite! (Status: {args.status})")

if __name__ == "__main__":
    main()
