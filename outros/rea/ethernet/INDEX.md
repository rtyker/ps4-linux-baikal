# Ethernet GBE Baikal (00:14.1) / Driver MTS — Índice do Acervo

## Estrutura
```
ethernet/
├── decompiled/          # Funções decompiladas do kernel Orbis (if_mts.c)
│   ├── mtsc_pci_attach_dc5a0070.txt        # Entrada PCI probe
│   ├── mts_attach_dc5a34f0.txt             # Attach interface rede
│   ├── decompiled_gbe_mac_attach.txt       # SceGbeMtsCtrl_attach
│   ├── decompiled_gbe_phy_attach.txt       # SceGbeMtsPhyCtrl_attach (thread gbe_phy_ctrl)
│   ├── decompiled_dc5a0ba0_gbe_phy_calib.txt  # Calibração PHY (66 it)
│   ├── decompiled_dc5a2680.txt             # MDIO packed read
│   ├── decompiled_dc5a2840.txt             # Clause 22 MDIO
│   ├── decompiled_dc5a2950.txt             # Clause 22 MDIO
│   ├── decompiled_dc5a3810.txt             # Desconhecido (mts_open?)
│   ├── decompiled_dc5a44c0.txt             # gbe_phy_ctrl — REVISADO 2026-07-30
│   ├── decompiled_dc5a5200.txt             # Referencia if_mts.c
│   ├── decompiled_dc5a6290.txt             # Referencia if_mts.c
│   ├── baikal_pcie_attach.txt              # PCIe attach Orbis
│   ├── baikal_pcie_attach_asm.txt
│   ├── baikal_pcie_attach_ghidra.txt
│   ├── baikal_pcie_probe.txt
│   ├── baikal_pcie_neighborhood.txt        # Lock do ACK do Glue (dc718b40)
│   └── mskc_attach_dc4c5140.txt            # Driver msk (Aeolia/Belize)
├── scans/               # Varreduras ao vivo
│   ├── hardware_report.txt                 # GBE em 00:14.1, BAR0 0xC2000000
│   ├── kernel_hardware_info.txt            # Strings: gbe0, gbe:ctrl, gbe:phy, gbe:rmu
│   ├── hardware_search_results.txt
│   ├── M8_leituras_glue.md                 # Leituras Glue BAR2
│   ├── M12_revalidacao.md                  # Revalidação BAR0 real
│   ├── glue_140000_180000_analise.txt      # Análise janela Glue
│   └── glue_140000_180000_raw.txt          # Dados brutos janela Glue
├── docs/                # Documentação do driver
│   ├── README.md                           # Doc consolidada do MTS
│   ├── PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md  # Plano completo (encerrado)
│   ├── RE_KERNEL_GBE_ATTACH.md             # RE do attach
│   ├── ICC_GBE_TEST_LOG.md                 # Logs testes ICC
│   ├── MARCO_HISTORICO_ETH0_MTS_BAIKAL.md  # Marco: eth0 com MAC real
│   ├── TESTES_HISTORICO.md                 # Histórico de testes
│   ├── MTS_INIT_SEQUENCE_dc5a31f0.md       # Sequência init MTS
│   ├── RE_IF_MSK.md                        # RE driver msk (Yukon)
│   ├── LEVANTAMENTO_HARDWARE_PS4_BAIKAL.md
│   ├── STATUS_DRIVERS_PS4_BAIKAL.md
│   ├── MARCOS_CONSOLIDADOS.md
│   ├── Kconfig
│   └── Makefile
├── harness/             # Scripts de teste ao vivo
│   ├── harness_gbe_mdio_probe.py           # Sonda PHY via MDIO
│   ├── harness_gbe_mac_enable.py           # Testa MAC enable
│   ├── harness_gbe_pci_command.py          # PCI config space
│   ├── harness_gbe_compare_working.py      # Compara hold/pulse
│   ├── harness_gbe_bar0_full_map.py        # Mapeia BAR0 completo
│   └── capture_dmesg.py                    # Captura dmesg remoto
└── plans/
    └── PLANO_DRIVER_ETHERNET_BAIKAL.md     # Plano (investigação encerrada)
```

## Dispositivo
- **PCI:** 104d:90d8 (00:14.1)
- **BAR0:** 0xC2000000 (4 KiB) — Registradores MAC
- **Driver Linux:** `mts.ko` (kernel/drivers_mts/mts.c)
- **Status:** MAC ligado, TX ~95%, **RX BLOQUEADO — PHY power-down**

## Conclusão da Investigação (2026-07-30)
> **Power-on físico do PHY é feito pelo firmware/bootloader Sony ANTES do kernel Orbis.**
> Não há sequência replicável via MDIO, ICC, SAMU ou RMU.
> **Investigação ENCERRADA** — reabrir apenas com fonte de dados nova.

## Próximos Passos Realistas
Ver `plans/PLANO_DRIVER_ETHERNET_BAIKAL.md` — corrigir warning MSI, ethtool ops, documentar limitação.
