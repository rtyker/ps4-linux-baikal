#!/usr/bin/env python3
"""
update_dangerous_registers.py — Popula o banco SQLite ps4_hardware_memory.db com todas as leituras
e operações comprovadamente DANOSAS/PERIGOSAS identificadas no projeto.
"""

import sqlite3

DB_PATH = "/mnt/t/downloads/PS4/linux_in_ps4/consolidado/ps4_hardware_memory.db"

def update_dangerous():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Adicionar coluna 'risk_level' se não existir
    try:
        cursor.execute("ALTER TABLE hardware_registers ADD COLUMN risk_level TEXT DEFAULT 'SAFE';")
    except sqlite3.OperationalError:
        pass # Coluna já existe

    dangerous_regs = [
        (
            "GbE PCI Config Space (>64B)",
            "ECAM (0xf80a1000)",
            "0x40..0xFF",
            "PCI_EXTENDED_CONFIG_READ",
            "DANOSO: Ler o espaço estendido de configuração PCI (>64 bytes) no sysfs (/sys/bus/pci/devices/0000:00:14.1/config) com a GbE sem clock congela o barramento PCI e derruba o console na hora.",
            0, 0, "HIGH_RISK_BUS_LOCKUP"
        ),
        (
            "Baikal Pervasive Glue",
            "BAR2 (0xc8800000)",
            "0x00000..0xFFFFF (Varredura Contígua)",
            "BAR2_SEQUENTIAL_BLOCK_READ",
            "DANOSO: Fazer leitura em bloco ou varredura sequencial em offsets não mapeados da BAR2 (0xc8800000) dispara desligamento instantâneo do PS4 pelo Southbridge. Apenas acessos pontuais em offsets validados são permitidos.",
            0, 0, "HIGH_RISK_POWER_OFF"
        ),
        (
            "GbE MMIO BAR0 (em Kexec)",
            "BAR0 (0xc2000000)",
            "0x11a / 0x100",
            "B2_CHIP_ID_DIRECT_KEXEC_READ",
            "DANOSO: Tentar ler registradores da BAR0 via Direct Map (PA_TO_DM) durante o cpu_quiesce_gate no kexec enquanto o MAC Yukon está em Hard Reset dispara exceção Bus Error / NMI no barramento x86, causando Kernel Panic.",
            0, 0, "HIGH_RISK_NMI_PANIC"
        ),
        (
            "FreeBSD TTY Subsystem",
            "Kernel Text",
            "kern.printf",
            "KEXEC_QUIESCE_PRINTF",
            "DANOSO: Chamar kern.printf() dentro do cpu_quiesce_gate() em linux_boot.c após interrupções limpas (cleanup_interrupts) e CPUs secundárias congeladas causa Deadlock/Spinlock Panic no FreeBSD.",
            0, 0, "HIGH_RISK_DEADLOCK"
        ),
        (
            "Baikal Pervasive Strobe",
            "BAR2 (0xc8800000)",
            "0x10a030",
            "PERVASIVE_CLOCK_RESET_STROBE",
            "ALTO RISCO: Registrador de estrobo/pulso autolimpo. Escrever sem a máscara exata de bits da GbE altera o clock-gating do Southbridge e causa tela preta / desconexão HDMI.",
            1, 0, "MEDIUM_RISK_CLOCK_GATING"
        )
    ]

    for item in dangerous_regs:
        # Verificar se já existe
        cursor.execute("SELECT id FROM hardware_registers WHERE reg_name = ?;", (item[3],))
        exists = cursor.fetchone()
        if not exists:
            cursor.execute("""
            INSERT INTO hardware_registers (device, base_bar, reg_offset, reg_name, description, safe_to_read, safe_to_write, risk_level)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """, item)
        else:
            cursor.execute("""
            UPDATE hardware_registers 
            SET description = ?, safe_to_read = ?, safe_to_write = ?, risk_level = ?
            WHERE reg_name = ?;
            """, (item[4], item[5], item[6], item[7], item[3]))

    conn.commit()
    conn.close()
    print("✅ Operações e registradores danosos cadastrados com sucesso no SQLite!")

if __name__ == "__main__":
    update_dangerous()
