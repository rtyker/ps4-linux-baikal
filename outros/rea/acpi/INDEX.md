# Baikal ACPI (00:14.0) — Índice do Acervo

## Estrutura
```
acpi/
├── decompiled/          # Funções decompiladas do kernel Orbis
│   ├── icc_power_dc528760.txt          # icc_power_shutdown
│   ├── icc_device_power_main_dc7c8b80.txt
│   ├── icc_devpower_get_dc7c8fb0.txt
│   ├── icc_devpower_set_dc7c8a70.txt
│   ├── icc_devpower_set_dc7c8a30.txt
│   ├── baikal_glue_write_dc718710.txt
│   ├── baikal_glue_block_reset_dc6df.txt
│   └── baikal_rtc_mvl.txt              # RTC via ICC (MMIO 0x5180000/0x5140000)
├── scans/               # Varreduras de hardware
│   ├── hardware_report.txt             # Mapeamento MMIO/I/O
│   └── kernel_hardware_info.txt        # Strings do kernel
├── docs/                # Documentação de referência
│   ├── LEVANTAMENTO_HARDWARE_PS4_BAIKAL.md
│   └── STATUS_DRIVERS_PS4_BAIKAL.md
└── plans/
    └── PLANO_DRIVER_ACPI_BAIKAL.md     # Plano de desenvolvimento
```

## Dispositivo
- **PCI:** 104d:90d7 (00:14.0)
- **BAR0 (MMIO):** 0xFDF8000000 (32 MiB) · **BAR2 (I/O):** 0x1000 (1 KiB) — medido ao vivo 2026-11-13 (não há BAR1)
- **I/O:** 0x1000 (1 KiB) — PM1a_EVT, PM1a_CNT, PM_TMR, GPE0
- **PM_TMR:** 0xFDF8001008

## Status (revisado 2026-11-13)
Plano revisado com evidência ao vivo: não é `platform_driver`, o BAR de I/O é BAR2, o núcleo ACPI já reclama PM1a/GPE0, o power button já existe via ICC e a DSDT tem 396 bytes sem objetos de dispositivo. O único candidato real é um watchdog (HPET/WDT em BAR2 `+0x109000`), e só se a leitura confirmar. Ver `plans/PLANO_DRIVER_ACPI_BAIKAL.md`.
