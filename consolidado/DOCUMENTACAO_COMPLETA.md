# Documentação Completa do Projeto PS4 Linux

## Visão Geral

Este projeto tem como objetivo executar Linux no PlayStation 4 (modelo RTYKER, Southbridge Baikal B1, firmware 12.52). O projeto inclui desde a preparação do hardware (HDD externo), instalação de distros, configuração de drivers gráficos (Mesa/Vulkan), até a criação de uma distro consolidada própria.

## Estrutura do Projeto

```
/mnt/t/downloads/PS4/linux_in_ps4/
├── CLAUDE.md                  # Regras + estado (carregado auto pelo assistente)
├── consolidado/               # Documentação consolidada (fonte única)
│   ├── MASTER_CONSOLIDADO.md  # Documento mestre
│   ├── LICOES_APRENDIDAS.md   # Lições imperativas
│   └── ... (50+ arquivos)
├── memory/                    # Memórias de sessões (24 arquivos)
├── scene-kmem-dumper/         # Payload dumper TCP (12.52)
├── ps4-payload-sdk/           # SDK C para payloads
├── ps4-linux-payloads/        # Payloads kexec Linux
├── scene-kernel-dumper/       # Dumper C original (USB, obsoleto)
├── kernels/                   # Kernels compilados
├── distros/                   # Distribuições Linux (~30)
├── initramfs/                 # Configs de initramfs
├── scripts/                   # Scripts auxiliares
├── all-ps4-payloads/          # Payloads diversos
├── kernel-framework-local/    # Framework kernel local
├── OpenOrbis/                 # Tools OpenOrbis
└── ps4-pup-unpacker/          # Extrator PUP
```

## Componentes Principais

### 1. PS4 Linux Payloads (kexec) - v24b.1
Sistema de boot que permite carregar o kernel Linux no PS4 via exploit. **Firmware agnóstico** - um único payload funciona para todos os firmwares (5.05 a 13.50) com detecção automática de southbridge (Baikal/Aeolia/Belize) e modelo (PRO ou não) em tempo de execução. Suporta VRAM de 32MB a 4GB via `vram.txt`.

### 2. Distribuições Linux
Mais de 30 distros disponíveis, baseadas em Arch, Fedora, Ubuntu/Debian e outras. A recomendada é Psxitarch v3.1.

### 3. Distro Consolidada (Arch PS4)
Distro própria baseada em Arch Linux com:
- Base: Arch Minimal v2 (bootstrap oficial limpo, ~400MB). O antigo *arch_minimal* (3.7GB) foi depreciado.
- Kernel estável: **Neocine 5.4.247-neocine-1.1** (Kernel Strawberry 7.0 causou falha no PS4 Pro Baikal).
- Correção de API: Systemd rebaixado de `261` para **`258.1-1`** (fixado via IgnorePkg) para evitar o travamento *"Failed to mount early API filesystems"*.
- GCC, Python 3.13, Go toolchain
- Drivers Mesa customizados para PS4
- Repositórios Arch + Chaotic-AUR + ps4-video
- Configuração de rede estática 192.168.6.150
- Usuário ps4 (senha: ps4) criado com sudo e root (senha: ps4).

### 4. Drivers Gráficos (Mesa/Vulkan)
Custom Mesa para PS4 com suporte Vulkan via RADV (driver AMD open-source).

## Especificações do Hardware

| Componente | Detalhe |
|------------|---------|
| Modelo | PS4-RTYKER |
| Firmware | 12.52 |
| Southbridge | Baikal B1 (0x30201) |
| HEN | 12.52 |
| GoldHEN | v2.4b18.9 |
| IP LAN | 192.168.6.130 |
| MAC LAN | 2C:CC:44:3F:69:5F |
| WIFI MAC | E8:D8:19:93:CC:AF |

## Fluxo de Trabalho

1. **Preparação**: Particionar HDD (sda1: 50MB FAT32, sda2: ext4)
   * *Atenção:* Nunca faça extrações de tarball ou manipulação de rootfs dentro de partições host NTFS (como `/mnt/t`), pois isso corrompe permissões Linux e bits setuid essenciais (gerando erros de boot no initramfs/systemd). Use `/mnt/hdauxiliar/temp` (partição ext4 nativa do host) se precisar de uma área temporária de trabalho no PC.
2. **Boot**: Copiar bzImage + initramfs.cpio.gz + bootargs.txt para sda1
3. **Distro**: Extrair distro tar para sda2
4. **Payload**: Carregar payload via Payload Guest app (3GB+)
5. **Pós-instalação**: Configurar timezone, locale, swap, drivers, pacotes
6. **Otimização**: Mesa/Vulkan, pinning de versões, scripts de atualização segura

## Scripts Automatizados

| Script | Função |
|--------|--------|
| `automatiza.sh` | Instalação completa automatizada |
| `pos_install.sh` | Configuração pós-instalação interativa |
| `fix_versions.sh` | Fixa versões de kernel/drivers no pacman |
| `verify_installation.sh` | Verifica se tudo está funcionando |
| `test_automatiza.sh` | Simulação do automatiza.sh (sem modificar disco) |
| `disable_sda2.sh` | Desativa montagem automática do sda2 |
| `build_latest_distro.sh` | Constrói a distro consolidada (com Kernel 7.0) |
| `build_payloads.sh` | Compila os payloads AIO de forma isolada |
| `formata_e_grava.sh` | Formata e extrai distro no HDD |
