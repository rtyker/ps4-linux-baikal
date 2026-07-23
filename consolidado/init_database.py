#!/usr/bin/env python3
"""
init_database.py — Cria e popula o banco de dados SQLite oficial do projeto PS4 Linux Baikal.
Banco: /mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db
"""

import sqlite3
import os

DB_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db"

def init_db():
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
        
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # 1. Tabela de Regiões de Memória e BARs PCI
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS bar_regions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device TEXT NOT NULL,
        pci_address TEXT NOT NULL,
        bar_name TEXT NOT NULL,
        phys_addr TEXT NOT NULL,
        size TEXT NOT NULL,
        purpose TEXT NOT NULL,
        status TEXT NOT NULL
    );
    """)

    # 2. Tabela de Registradores Específicos Mapeados
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS hardware_registers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device TEXT NOT NULL,
        base_bar TEXT NOT NULL,
        reg_offset TEXT NOT NULL,
        reg_name TEXT NOT NULL,
        description TEXT NOT NULL,
        safe_to_read INTEGER NOT NULL,
        safe_to_write INTEGER NOT NULL,
        risk_level TEXT DEFAULT 'SAFE'
    );
    """)

    # 3. Tabela de Histórico de Testes e Resultados
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS test_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        phase TEXT NOT NULL,
        test_name TEXT NOT NULL,
        target_component TEXT NOT NULL,
        action_taken TEXT NOT NULL,
        status TEXT NOT NULL,
        complementary_info TEXT NOT NULL
    );
    """)

    # --- INSERINDO REGIÕES DE MEMÓRIA E BARS ---
    bar_data = [
        ("GbE Ethernet", "0000:00:14.1", "BAR0", "0xc2000000", "4KB", "Registradores MAC Marvell Yukon (B2_CHIP_ID, etc.)", "MAPPED_D0"),
        ("Baikal Pervasive Glue", "0000:00:14.4", "BAR2", "0xc8800000", "1MB", "Glue Logic Baikal (Clock gating, reset, pulse/hold)", "MAPPED"),
        ("Baikal Trimming/Efuses", "0000:00:14.4", "BAR4", "0xc9000000", "64KB", "Efuses de Trim (PHY calibration, SATA/USB/GbE)", "MAPPED"),
        ("PCI ECAM Config", "PCI Bus 0", "ECAM", "0xf8000000", "256MB", "PCI Configuration Space (Slot 20 / 00:14.1 = 0xf80a1000)", "MAPPED_ECAM"),
        ("GPU AMD Radeon", "0000:00:01.0", "BAR0", "0xe4800000", "16MB", "Registradores de controle GFX/CP/SDMA AMD", "MAPPED"),
        ("IOMMU Baikal", "System", "MMIO", "0xfc000018", "64B", "Registrador de controle/disable da IOMMU Baikal", "MAPPED_KEXEC"),
        ("SATA AHCI Controller", "0000:00:14.2", "BAR5", "0xc0000000", "4KB", "Controlador AHCI SATA do disco interno", "MAPPED")
    ]
    cursor.executemany("""
    INSERT INTO bar_regions (device, pci_address, bar_name, phys_addr, size, purpose, status)
    VALUES (?, ?, ?, ?, ?, ?, ?);
    """, bar_data)

    # --- INSERINDO REGISTRADORES CHAVE ---
    reg_data = [
        ("GbE Ethernet", "BAR0 (0xc2000000)", "0x11a", "B2_CHIP_ID", "ID do Chip Marvell Yukon (Lê 0x00 se MAC preso em Hard Reset)", 1, 0),
        ("GbE Ethernet", "BAR0 (0xc2000000)", "0x11b", "B2_MAC_CFG", "Configuração/Revisão do MAC Marvell Yukon", 1, 0),
        ("Baikal Pervasive Glue", "BAR2 (0xc8800000)", "0x10a030", "PERVASIVE_CLOCK_PULSE", "Strobe/Pulso de liberação de clock/reset (SATA/USB/GbE)", 0, 1),
        ("Baikal Trimming", "BAR4 (0xc9000000)", "0xc06c", "EFUSE_TRIM_SHARED", "Efuse de validação PHY (bits 23/31 para GbE, bits 18/26 para SATA)", 1, 0),
        ("GbE PCI Config", "ECAM (0xf80a1000)", "0x04", "PCI_COMMAND", "Command Register PCI (0x0542: Memory Space e Bus Master Habilitados)", 1, 1),
        ("GbE PCI Config", "ECAM (0xf80a1000)", "0xf4", "PMCSR", "Power Management Control/Status (0x0000: Estado D0 - Full Power)", 1, 1)
    ]
    cursor.executemany("""
    INSERT INTO hardware_registers (device, base_bar, reg_offset, reg_name, description, safe_to_read, safe_to_write)
    VALUES (?, ?, ?, ?, ?, ?, ?);
    """, reg_data)

    # --- INSERINDO HISTÓRICO DE TESTES ---
    tests_data = [
        ("2026-07-20 14:00", "Fase 1", "Teste M1-M7 ICC Power-on", "GbE / Syscon", "Envio de payloads ICC Major 5 via Linux", "REFUTED", "Nenhum payload ICC liga GbE via Linux. Major 5 é exclusivo do Wi-Fi/BT."),
        ("2026-07-21 10:00", "Fase 3", "Vaccine V1 - Patch ret 0xC3", "SceGbeMtsCtrl", "Injeção de 0xC3 no detach/shutdown do Orbis", "FAIL_PANIC", "Erro de sintaxe no ASM inline (CR0 corrupto) gerou #GP e panic no Orbis."),
        ("2026-07-21 16:00", "Fase 3", "Vaccine V2 - Patch xor eax,eax; ret", "SceGbeMtsCtrl", "Anulação completa de detach/shutdown no Orbis", "FAIL_PANIC", "O DMA da GbE continuou ativo e escreveu na memória do Linux durante o boot, corrompendo o kexec."),
        ("2026-07-21 21:00", "Fase 3", "Vaccine V3 - Patch NOP no call ICC", "SceGbeMtsCtrl", "NOP no call 0x147001e (offset 0x250b6e)", "FAIL_PANIC", "Anular a rotina de shutdown faz a GbE permanecer ativa no D3 do PCI, gerando AER Fatal Error no kexec."),
        ("2026-07-21 23:00", "Fase 4", "Loop Genérico PCI D0", "PCI Bus 0", "Loop em linux_boot.c forçando D0 em todos os PCI slots", "FAIL_COLLATERAL", "Linux bootou e Telnet funcionou, mas congelou o controlador SATA ata1. ChipID da GbE continuou 0x0."),
        ("2026-07-22 07:00", "Fase 5", "Leitura MMIO no cpu_quiesce_gate", "kexec / linux_boot.c", "Acesso MMIO BAR0 e kern.printf pós-IRQs desativadas", "FAIL_PANIC", "kern.printf sem IRQs deu Spinlock Deadlock. Leitura MMIO com MAC em reset disparou Bus Error / NMI."),
        ("2026-07-22 07:05", "Fase 5", "Diagnóstico ao Vivo Telnet Config Space", "GbE PCI Config 00:14.1", "Dump do PCI Config Space via hexdump/Telnet", "OK", "Confirmado 100% que GbE está em D0 (PMCSR 0x0000) e Command 0x0542 (Memory Decode On). O problema é Hard Reset no MAC."),
        ("2026-07-22 07:18", "Fase 5", "Reversão Total do linux_boot.c", "kexec codebase", "Git checkout de linux_boot.c e rebuild limpo", "OK", "Payload linux-1024mb.bin 100% original e restaurado sem riscos no boot do FreeBSD.")
    ]
    cursor.executemany("""
    INSERT INTO test_history (timestamp, phase, test_name, target_component, action_taken, status, complementary_info)
    VALUES (?, ?, ?, ?, ?, ?, ?);
    """, tests_data)

    conn.commit()
    conn.close()
    print(f"Banco de dados SQLite inicializado e populado com sucesso em: {DB_PATH}")

if __name__ == "__main__":
    init_db()
