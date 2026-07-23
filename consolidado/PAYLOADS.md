# Documentação dos Payloads kexec para PS4 Linux

## Visão Geral

Os payloads kexec são responsáveis por carregar o kernel Linux no PS4 a partir do OrbisOS. Usam o exploit do GoldHEN para executar kexec (kernel exec) - carrega e pula para um novo kernel sem reinicializar o hardware.

**NOVA ARQUITETURA (v24+)**: A partir de Abril/2026, os payloads são **firmware agnósticos**. Um único payload funciona em TODOS os firmwares (5.05 a 13.50) com detecção automática de southbridge (Baikal/Aeolia/Belize) e modelo (PRO ou não) em **tempo de execução**. Não existem mais payloads separados por firmware ou southbridge.

## Repositório

```bash
git clone https://github.com/ps4-linux/ps4-linux-loader
cd ps4-linux-loader/linux
make
```

## Firmwares Suportados

Um único binário para todos:

| Firmware | Status |
|----------|--------|
| 5.05 | Suportado |
| 6.72 | Suportado |
| 7.00 / 7.01 / 7.02 | Suportado |
| 7.50 / 7.51 / 7.55 | Suportado |
| 8.00 / 8.01 / 8.03 | Suportado |
| 8.50 / 8.52 | Suportado |
| 9.00 | Suportado |
| 9.03 / 9.04 | Suportado |
| 9.50 / 9.51 / 9.60 | Suportado |
| 10.00 / 10.01 | Suportado |
| 10.50 / 10.70 / 10.71 | Suportado |
| 11.00 | Suportado |
| 11.02 | Suportado |
| 11.50 / 11.52 | Suportado |
| 12.00 / 12.02 | Suportado |
| 12.50 / 12.52 | Suportado |
| 13.00 | Suportado |
| 13.02 / 13.04 | Suportado |
| 13.50 | Suportado |

## Estrutura do Payload (v24)

O código fonte foi completamente reestruturado para eliminar duplicação:

```
linux/
├── Makefile                  # Build - gera payloads para 32MB a 4GB VRAM
├── main-aio.c                # Entry point único do payload AIO
├── fw_detect.c / fw_detect.h # Detecção runtime do firmware
├── sb_detect.h               # Detecção runtime da southbridge
├── fw_offsets.h              # Offsets por firmware
├── aio_types.h / magic.h     # Tipos e magic numbers
├── ps4-kexec-common/         # Código kexec COMPARTILHADO (NÃO duplicado)
│   ├── kexec.c / kexec.h     # Implementação principal do kexec
│   ├── kernel.c / kernel.h   # Carregamento do kernel
│   ├── linux_boot.c / .h     # Inicialização do Linux
│   ├── firmware.c / .h       # Configuração de firmware
│   ├── acpi.c / .h           # Tabelas ACPI
│   ├── crc32.c / .h          # Checksums
│   ├── uart.c / .h           # Console serial UART
│   ├── linux_thunk.S         # Assembly thunk (transição 64-bit)
│   ├── types.h / string.h    # Tipos e funções de string
│   ├── x86.h / reboot.h      # Definições x86 e reboot
│   ├── elf.h / acpi_caps.h   # ELF loader e ACPI caps
│   ├── kexec.ld              # Linker script
│   └── Makefile              # Build do kexec
├── lib/                      # Biblioteca de sistema
│   ├── crt.asm / syscalls.asm / syscalls.py / dl.c
│   └── Makefile
└── freebsd-headers/          # Headers FreeBSD para compilação
```

## Controle de VRAM via vram.txt

A VRAM é controlada por um arquivo de texto simples contendo o valor em **MB**:

| vram.txt | VRAM Alocada | Uso |
|----------|-------------|-----|
| `32` | 32 MB | Server headless mínimo |
| `64` | 64 MB | Server headless |
| `128` | 128 MB | Server com display básico |
| `256` | 256 MB | Server |
| `512` | 512 MB | Server |
| `1024` | 1 GB | **Padrão** - Desktop/Gaming |
| `2048` | 2 GB | Gaming |
| `3072` | 3 GB | Gaming pesado |
| `4096` | 4 GB | Máximo |

**Nota**: Padrão é 1GB. VRAM.txt tem prioridade sobre o valor embutido no payload.

## VRAMs Pré-Compiladas

O build gera payloads para todos os tamanhos: `linux-32mb.bin` até `linux-4096mb.bin`

## Carregamento dos Payloads

### Via Payload Guest App (recomendado)
1. Instale o Payload Guest pela loja
2. Selecione o payload `.elf` (preferencial) ou `.bin`
3. Para seu PS4 (FW 12.52, Baikal), use qualquer payload (ex: `linux-3072mb.bin`)

### Via GoldHEN PayLoader / PSFree-Enhanced
Abra o host: https://arabpixel.github.io/PSFree-Enhanced

### Via NetCat (nc)
```bash
# Não precisa mais especificar firmware ou southbridge:
nc -w 3 192.168.6.130 9090 < linux-3072mb.bin
```

## Formato dos Arquivos

- **.elf**: Formato recomendado para GoldHEN v2.4b18.5+
- **.bin**: Gerado a partir do .elf via `objcopy`

## Caminhos de Boot

O payload procura os arquivos de boot em ordem:
1. **USB/HDD Externo** (prioridade máxima): Partição FAT32
2. **HDD Interno caminho 1**: `/data/linux/boot/`
3. **HDD Interno caminho 2 (fallback)**: `/user/system/boot/` (novo em v23+)

### Arquivos necessários:
- `bzImage` - Kernel do Linux
- `initramfs.cpio.gz` - Initramfs
- `bootargs.txt` (opcional) - Parâmetros de linha de comando do kernel
- `vram.txt` (opcional) - Configuração de VRAM em MB

## UART Console

Para debug via serial adicione ao bootargs.txt:
- **Aeolia/Belize**: `console=uart8250,mmio32,0xd0340000`
- **Baikal**: `console=uart8250,mmio32,0xC890E000`

## Funcionalidades

- **Firmware agnóstico**: Um payload para todos os firmwares (5.05 a 13.50)
- **Detecção runtime de southbridge**: Não precisa mais escolher Baikal vs Belize
- **Detecção runtime de PRO**: Não precisa mais de payload separado para PS4 Pro
- **VRAM variável**: 32MB a 4GB via payload ou vram.txt
- **Boot automático**: Arquivos copiados para `/data/linux/boot` no HDD interno
- **RTC via cmdline**: Tempo do OrbisOS passado ao kernel via `time=CURRENTTIME`
- **Fallback path**: `/user/system/boot/` se `/data/linux/boot/` não existir
- **Rescue shell**: Boot sem USB (via FTP para `/data/linux/boot/`)

## How to Build

```bash
git clone https://github.com/ps4-linux/ps4-linux-loader
cd ps4-linux-loader/linux
make
```

Isso gera: `payloads/linux-32mb.bin` até `payloads/linux-4096mb.bin`

## Changelog

| Versão | Data | Mudanças |
|--------|------|----------|
| **v24b.1** | 11 Mai 2026 | Suporte FW 13.04 e 13.50, refactor GitHub Actions |
| v24b | 03 Abr 2026 | Bugfix detecção firmware < 10.71, correção 10.50 |
| v24 | 02 Abr 2026 | **Payload firmware agnóstico** + detecção runtime southbridge/PRO |
| v23 | 28 Mar 2026 | Suporte FW 7.xx e 8.xx, fallback path `/user/system/boot/` |
| v22 | 23 Mar 2026 | Payloads server 128/256/512MB, suporte 32MB VRAM |
| v21.5 | 14 Fev 2026 | Suporte FW 13.02, fix tela preta PS4 Pro 12.5x |
