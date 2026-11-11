# Informações de Hardware — PS4 Pro Baikal (FW 12.52)

Documentação gerada a partir dos dados coletados via SSH na console ativa em **2026-07-13**.

## 1. Dispositivos PCI (Saída do `lspci -nnk`)

Abaixo estão os IDs de hardware e os drivers correspondentes que estão ativos no kernel Neocine:

*   **Processador / Root Complex**:
    *   `[00:00.0] Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Liverpool Processor Root Complex [1022:1436]`
*   **Unidade de Gerenciamento de E/S (IOMMU)**:
    *   `[00:00.2] IOMMU [0806]: Advanced Micro Devices, Inc. [AMD] Liverpool I/O Memory Management Unit [1022:1437]`
*   **Placa de Vídeo Integrada (APU)**:
    *   `[00:01.0] VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Gladius [1002:9924]`
    *   *Driver em uso:* `amdgpu`
*   **Controlador de Áudio HDMI/DP**:
    *   `[00:01.1] Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Liverpool HDMI/DP Audio Controller [1002:9921]`
    *   *Driver em uso:* `snd_hda_intel`
*   **Dummy Host Bridge**:
    *   `[00:02.0] Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Liverpool UMI PCIe Dummy Host Bridge [1022:1438]`
*   **Baikal ACPI**:
    *   `[00:14.0] System peripheral [0880]: Sony Corporation Baikal ACPI [104d:90d7]`
*   **Controlador Ethernet Baikal (Rede Cabeada)**:
    *   `[00:14.1] System peripheral [0880]: Sony Corporation Baikal Ethernet Controller [104d:90d8]`
    *   *Driver em uso:* **Nenhum** (Desativado no código do kernel em `sky2.c`)
*   **Controlador SATA AHCI (Disco)**:
    *   `[00:14.2] System peripheral [0880]: Sony Corporation Baikal SATA AHCI Controller [104d:90d9]`
*   **Controlador de Cartão SD / Leitor**:
    *   `[00:14.3] System peripheral [0880]: Sony Corporation Baikal SD/MMC Host Controller [104d:90da]`
    *   *Driver em uso:* `sdhci-pci`
*   **PCI Express Glue e Dispositivos Variados (Baikal PCIe)**:
    *   `[00:14.4] System peripheral [0880]: Sony Corporation Baikal PCI Express Glue and Miscellaneous Devices [104d:90db]`
    *   *Driver em uso:* `baikal_pcie`
*   **Controlador de DMA**:
    *   `[00:14.5] System peripheral [0880]: Sony Corporation Baikal DMA Controller [104d:90dc]`
*   **Controlador de Memória DDR3/SPM**:
    *   `[00:14.6] System peripheral [0880]: Sony Corporation Baikal Memory (DDR3/SPM) [104d:90dd]`
*   **Controlador USB 3.0 (xHCI)**:
    *   `[00:14.7] System peripheral [0880]: Sony Corporation Baikal USB 3.0 xHCI Host Controller [104d:90de]`
    *   *Driver em uso:* `xhci_aeolia`
*   **Pontes HT do Processador Liverpool**:
    *   `[00:18.0]` a `[00:18.6]` — Pontes de comunicação interna do processador AMD
    *   *Drivers em uso:* `k10temp` (monitor de temperatura) e `fam15h_power` (monitor de energia).

---

## 2. Parâmetros de Rede Ativos (Interface Wireless)

*   **Interface Sem Fio**: `wlan0` (MediaTek MT7668)
*   **MAC Address**: `00:0c:43:26:60:48`
*   **IP Dinâmico obtido**: `192.168.6.127`
*   **IP do PC Host (para ARP Estático)**: `192.168.6.100` (interface `wlp0s20f3`)
*   **IP do Roteador / Gateway**: `192.168.6.1`

---

## 3. Identificação do Kernel Rodando

*   **Uname**:
    `Linux ps4-arch 5.4.247-neocine-1.1-g7f796666a956-dirty #1 SMP Mon Jul 13 13:26:55 -03 2026 x86_64 GNU/Linux`

---

## 4. Status de Módulos (`lsmod`)

*   **Módulos de kernel carregados dinamicamente**: Nenhum. Os drivers essenciais (`amdgpu`, `xhci_aeolia`, `baikal_pcie` e drivers de som/Wi-Fi) foram compilados como embutidos (**built-in**) no kernel Neocine, dispensando o uso de arquivos de módulos `.ko`.
