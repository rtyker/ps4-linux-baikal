# Informações do Hardware PS4

## Especificações do PS4 RTYKER

| Componente | Detalhe |
|------------|---------|
| **Modelo** | PS4-RTYKER |
| **Firmware** | 12.52 |
| **Southbridge** | Baikal B1 (0x30201) |
| **HEN** | 12.52 |
| **GoldHEN** | v2.4b18.9 |
| **IP LAN** | 192.168.6.130 |
| **MAC LAN** | 2C:CC:44:3F:69:5F |
| **WiFi MAC** | E8:D8:19:93:CC:AF |

## Southbridges do PS4

O PS4 possui diferentes southbridges dependendo da revisão do hardware:

| Southbridge | Modelos | EMC Timer Base | UART Base | PCI IDs |
|-------------|---------|----------------|-----------|---------|
| **Aeolia** | PS4 Phat (primeiros) | `0xd0281000` | `0xd0340000` | 0x908f-0x90a4 |
| **Belize** | PS4 Slim, PS4 Pro | `0xd0281000` | `0xd0340000` | 0x908f-0x90a4 |
| **Baikal** (B1) | PS4 Slim/Pro (revisões recentes) | **N/A** (layout diferente) | `0xC890E000` | 0x90d7-0x90de |

### PCI IDs Baikal (Linux)
| Device | ID | Driver |
|--------|-----|--------|
| ACPI | `0x90d7` | — |
| GBE (Ethernet) | `0x90d8` | sky2.c |
| AHCI (SATA) | `0x90d9` | ahci.c |
| SDHCI (eMMC) | `0x90da` | sdhci-pci-core.c |
| PCIe (Glue) | `0x90db` | ps4-apcie.c |
| DMAC | `0x90dc` | — |
| MEM | `0x90dd` | — |
| XHCI (USB) | `0x90de` | xhci-aeolia.c |

### ⚠️ Incompatibilidade: BAR4 Glue Logic
A southbridge Aeolia/Belize usa **PCI function 4 (BAR4)** como registradores de configuração ("glue logic") para mapear todos os dispositivos. Em Baikal B1, **function 4 pode ter layout diferente**, causando:
- `pci_ioremap_bar(dev, 4)` → NULL
- `apcie_glue_init()` → falha
- Todos os dispositivos (SATA, GPU, USB) → **não inicializam**

**Correção no kernel 5.15**: Skip de glue_init quando `is_baikal == true`.

A southbridge é a ponte sul do chipset, responsável por:
- Controladora USB
- Áudio
- Rede
- Armazenamento
- GPIO

O tipo de southbridge afeta quais payloads kexec são compatíveis.

## APU (CPU + GPU)

O PS4 usa uma APU AMD personalizada (Jaguar):
- **CPU**: 8-core AMD Jaguar x86-64 (1.6 GHz)
- **GPU**: AMD GCN (Graphics Core Next) 1.8 TFLOPS
- **RAM**: 8GB GDDR5 (unificada CPU+GPU)
- **TSC Frequency**: 1.594 GHz (PS4_DEFAULT_TSC_FREQ)
- **LAPIC Timer**: Calibrado via EMC timer (Aeolia) ou default (Baikal)

## Limitações de Hardware para Linux

### RAM
- **Total**: 8GB GDDR5
- **Disponível para Linux**: ~4-5GB (OrbisOS reserva o resto)
- **Swap**: ESSENCIAL - Recomendado 8-12GB

### Vídeo
- Driver AMD open-source (Radeon/RADV)
- Resolução máxima: 1080p@60Hz (alguns kernels suportam 4K)
- Problemas comuns: tela preta em monitores (resolvido com EDID falso)
- **Solução para monitor LG**: adaptador HDMI-VGA **COM USB de energia**.
  Adaptadores HDMI-VGA sem alimentação USB não funcionam no PS4 -
  a saída HDMI do PS4 não fornece energia suficiente para o chip
  conversor. O cabo USB precisa estar conectado a uma fonte de
  5V (carregador USB, porta USB do PS4, etc.).

### Wi-Fi
- Chipset MediaTek MT76
- Funciona com driver `mt76` do kernel
- Pode ser instável em alguns kernels

### Bluetooth
- Controladora Bluetooth integrada
- Suporte limitado no Linux

### Áudio
- HDMI audio funciona
- Áudio analógico via controle pode ser complicado

## Configurações Recomendadas de Vídeo (OrbisOS)

Antes de carregar o payload Linux:
1. Resolução: 1080p
2. Gama RGB: Completa
3. HDR: Desligado
4. HDCP: Desabilitado
5. HDMI device link: Desabilitado
6. Saída de cor intensa: Desligado

## Payload Guest App

- Use preferencialmente payload de 3GB (3072MB) para desktop ou 1GB (1024MB) para instalação
- GoldHEN v2.4b18.5+ recomenda arquivos .elf
- **Payloads v24+ são firmware agnósticos**: um único payload para todos os firmwares
- Carregamento via BinLoader do host PSFree-Enhanced
- VRAM ajustável via `vram.txt` (32MB a 4GB)
- Para uso como servidor: 32MB-512MB libera RAM para o sistema

## Endereços Importantes

- **Payload sender port**: 9090
- **FTP port**: 2121 (GoldHEN FTP)
- **PS4 Remote Play**: Chiaki app
