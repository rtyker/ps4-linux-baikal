# Resumo Técnico - PS4 Linux

Este é o resumo técnico para contextualização rápida de um agente IA sobre o projeto de Linux no PS4.

## Projeto: Linux no PlayStation 4

### Hardware Alvo
- **Modelo**: PS4 RTYKER (firmware 12.52)
- **Southbridge**: Baikal B1 (0x30201) - endereço UART: `0xC890E000`
- **GoldHEN**: v2.4b18.9
- **IP**: 192.168.6.130

### Estado Atual
- Linux funcional com múltiplas distros
- Distro recomendada: Psxitarch v3.1 (ITmania) - LXDE, leve, funcional
- Base de Testes e Desenvolvimento: **Arch Minimal v2** (bootstrap oficial Arch Linux 2026 de ~400MB, limpo). O antigo *arch_minimal* (3.7GB) foi depreciado e mantido apenas para referência histórica.
- Kernel estável: **Neocine 5.4.247-neocine-1.1** (Consolidação com Kernel Strawberry 7.0 falhou devido a travamento precoce com luz branca no PS4 Pro Baikal FW 12.52).
- Drivers gráficos Mesa/Vulkan funcionais (com Mesa customizado do noob404)
- Correção Crítica do Boot (Arch Minimal v2): Downgrade do `systemd` de `261.1-1` para `258.1-1` via `arch-chroot` para solucionar o erro *"Failed to mount early API filesystems"* no kernel 5.4. **ATENÇÃO:** Usar apenas `pacman -U --noconfirm --nodeps` (sem `--dbonly`). O uso de `--dbonly` + `--nodeps` separadamente deixa symlinks .so apontando para a versão antiga e arquivos .pacnew, causando falha de boot.

### Fluxo de Instalação
1. Particionar HDD: sda1 (50MB FAT32) + sda2 (ext4)
2. Copiar bzImage + initramfs.cpio.gz + bootargs.txt para sda1
3. Extrair distro tar para sda2
4. Carregar payload via Payload Guest (3GB+) no PS4
5. Executar pós-instalação (pos_install.sh)

### Parâmetros de Boot Otimizados
```
video=HDMI-A-1:1920x1080@60e panic=0 clocksource=tsc consoleblank=0
net.ifnames=0 radeon.dpm=0 amdgpu.dpm=0 drm.debug=0
console=uart8250,mmio32,0xC890E000 console=ttyS0,115200n8 console=tty0
drm.edid_firmware=edid/1920x1080.bin
```

### Pontos Críticos
1. **Swap é obrigatório** (8GB+) - PS4 tem pouca RAM disponível (~4GB)
2. **DisableSandbox** no pacman.conf - necessário para kernels PS4
3. **Fixar versões** (fix_versions.sh) - kernel e Mesa não podem ser atualizados livremente
4. **Tela preta em monitores** - resolvido com EDID falso e parâmetro video
5. **DPM desligado** (radeon.dpm=0 amdgpu.dpm=0) - essencial para estabilidade
6. **Preservação de Permissões (Host NTFS)** - Evite extrair ou manipular rootfs de distros na partição NTFS `/mnt/t`, pois perde-se metadados Linux e permissões setuid (gerando erros como *failed to mount early API filesystems*). Use `/mnt/hdauxiliar/temp` (partição ext4 nativa) para operações temporárias confiáveis.

### Scripts Principais
| Script | Função |
|--------|--------|
| `automatiza.sh` | Instalação completa automatizada |
| `pos_install.sh` | Pós-instalação interativa |
| `fix_versions.sh` | Fixa versões de pacotes críticos |
| `verify_installation.sh` | Verificação do sistema |
| `build_latest_distro.sh` | Constrói a distro consolidada (com Kernel 7.0) |
| `build_payloads.sh` | Compila os payloads AIO de forma isolada |

### Drivers Gráficos
- Mesa oficial: `pacman -S mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon`
- Mesa customizado (noob404): Para melhor suporte Vulkan no PS4
- RADV = Radeon Open-Source Vulkan Driver
- Repositório PS4 video: `https://centi07.github.io/repo/`

### Repositórios Importantes
- payloads: https://github.com/ps4-linux/ps4-linux-loader (v24b.1 - firmware agnóstico)
- kernel baikal 7.0: https://github.com/rmuxnet/linux (branch baikal/7.0.8-Stable)
- kernel baikal 5.4: https://github.com/feeRnt/ps4-linux-12xx (v5.4.247-neocine-1.1)
- kernel baikal MT7668+VPN: https://github.com/noob404yt/baikal-5.4.213-mt7668-dns-vpn
- mesa custom: https://github.com/noob404yt/ps4-custom-mesa-archlinux
- arch ps4: https://github.com/centi07/arch-ps4-aur

### Diretório de Trabalho
```
/mnt/t/downloads/PS4/
└── linux_in_ps4/
    ├── automatiza.sh / pos_install.sh / fix_versions.sh / verify_installation.sh
    ├── distros/       # ~30 distros disponíveis
    ├── kernels/       # Kernels 4.14 a 5.4 + xanmod
    ├── ps4-linux-payloads/  # Payload v24b.1 (firmware agnóstico)
    └── consolidado/   # Distro consolidada (preferencial)
        ├── build_latest_distro.sh
        ├── build_payloads.sh
        ├── rootfs/    # Arch Linux rootfs completo
        └── DOCUMENTACAO_COMPLETA.md  # Esta documentação
```

### Payloads
**A partir de v24 (Abr 2026)**: Payload firmware agnóstico - UM único payload para TODOS os firmwares (5.05 a 13.50). Detecção automática de southbridge (Baikal) e modelo (PRO ou não) em tempo real. VRAM configurável via `vram.txt` (32MB a 4GB).

### Otimizações para Gaming
- Proton 8.0: Melhor compatibilidade até o momento
- Parâmetros: `RADV_PERFTEST=gpl DXVK_STATE_CACHE=1 DXVK_ASYNC=1 gamemoderun %command%`
- Overwatch funcionou (lento) com Proton 8.0

### Distro Consolidada (build_latest_distro.sh)
- Base: Arch Linux (arch_minimal_v2.tar / bootstrap limpo)
- Kernel: 5.4.247-neocine (Estável e Consolidado para Baikal)
- Correção de API: Systemd fixado na versão `258.1-1` (downgrade obrigatório para compatibilidade de cgroups/proc com kernel 5.4)
- IP estático: 192.168.6.150/24
- Usuário: ps4 (senha: ps4)
- Root: ps4 (senha: ps4)
- Chaotic-AUR configurado
- Mesa PS4 customizado incluído
- DisableSandbox ativado
- Kernel e drivers fixados (IgnorePkg)
