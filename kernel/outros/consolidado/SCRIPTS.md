# Documentação de Scripts do PS4 Linux

## Scripts de Instalação

### automatiza.sh
**Path**: `linux_in_ps4/automatiza.sh`

Script completo de instalação automatizada. Executa:
1. Validação de entrada (sudo, parâmetros, arquivo, disco)
2. Configuração de pontos de montagem
3. Criação de partições (fdisk)
4. Formatação (FAT32 + ext4)
5. Cópia de arquivos de boot (bzImage, initramfs, bootargs)
6. Extração da distro (tar.xz ou tar)
7. Limpeza final

**Uso**: `sudo ./automatiza.sh <distro_tar_file>`
**Exemplo**: `sudo ./automatiza.sh distros/psxitarch3.1-unoficial/psxitarch_v3.1-ITm.tar.xz`

### test_automatiza.sh
**Path**: `linux_in_ps4/test_automatiza.sh`

Modo de simulação do automatiza.sh. Útil para validar o fluxo sem modificar o disco real.

**Uso**: `sudo ./test_automatiza.sh <distro_tar_file>`

### formata_e_grava.sh
**Path**: `linux_in_ps4/distros/formata_e_grava.sh`

Script simplificado que apenas formata o sda2 e extrai a distro. Mais leve que o automatiza.sh.

**Uso**: `sudo ./formata_e_grava.sh <distro_tar.xz>`

## Scripts de Pós-Instalação

### pos_install.sh
**Path**: `linux_in_ps4/pos_install.sh`

Script interativo que automatiza toda a configuração pós-instalação. Passos:
1. Configuração de timezone (America/Sao_Paulo)
2. Configuração de locale (pt_BR)
3. Swap (8GB com swappiness=90)
4. Verificação da idade da distro
5. Reset do banco de dados do pacman
6. Atualização do sistema
7. Configuração Mesa/Vulkan
8. Mesa customizado (opcional)
9. Instalação de pacotes adicionais (Steam, RetroArch, joystick)
10. Verificação final do sistema

**Uso**: `sudo ./pos_install.sh`

### fix_versions.sh
**Path**: `linux_in_ps4/fix_versions.sh`

Script para fixar versões de pacotes críticos no pacman, prevenindo que atualizações quebrem o sistema.

**O que cria**:
- `/etc/pacman.conf.d/ps4-version-pinning.conf` - Fixa kernel, mesa, vulkan
- `/etc/pacman.conf.d/ps4-blacklist.conf` - Blacklist de pacotes problemáticos
- `/usr/local/bin/ps4-safe-update` - Script de atualização segura
- `/usr/local/bin/ps4-backup-kernel` - Script de backup do kernel

**Uso**: `sudo ./fix_versions.sh`

### verify_installation.sh
**Path**: `linux_in_ps4/verify_installation.sh`

Script de verificação que checa todos os componentes do sistema.

**Verificações**:
- Informações do sistema (hostname, kernel, arch, uptime)
- Configuração de tempo (timezone, NTP, RTC)
- Configuração de locale (pt_BR, keymap br-abnt2)
- Swap (ativo, tamanho, swappiness)
- Disco (partições, boot files)
- Pacotes (total, atualizações disponíveis)
- Gráficos (Vulkan, OpenGL)
- Rede (gateway, DNS, NetworkManager)
- Usuários

**Uso**: `sudo ./verify_installation.sh`

## Scripts Utilitários

### disable_sda2.sh
**Path**: `linux_in_ps4/disable_sda2.sh`

Desativa completamente a montagem automática do /dev/sda2 (disco de teste do PS4) no sistema host. Remove entradas do fstab, desativa journal do ext4, cria unidades systemd para bloquear montagem.

**Uso**: `sudo ./disable_sda2.sh`

### disable_sda2_simple.sh
**Path**: `linux_in_ps4/disable_sda2_simple.sh`

Versão simplificada do disable_sda2.sh. Remove entradas do fstab, desativa journal, bloqueia montagem.

**Uso**: `sudo ./disable_sda2_simple.sh`

### umount_all.sh
**Path**: `linux_in_ps4/distros/umount_all.sh`

Simples script para desmontar sda1 e sda2.

**Uso**: `sudo ./umount_all.sh`

## Scripts de Mesa/Vulkan

### mesa.sh
**Path**: `linux_in_ps4/distros/mesa/mesa.sh`

Configura variáveis de ambiente para usar o Mesa customizado do noob404 para PS4.

```bash
MESA=/home/noob404/mesa
export LD_LIBRARY_PATH=$MESA/lib64:$MESA/lib:$LD_LIBRARY_PATH
export LIBGL_DRIVERS_PATH=$MESA/lib64/dri:$MESA/lib/dri
export VK_ICD_FILENAMES=$MESA/share/vulkan/icd.d/radeon_icd.x86_64.json:$MESA/share/vulkan/icd.d/radeon_icd.x86.json
export D3D_MODULE_PATH=$MESA/lib64/d3d/d3dadapter9.so.1:$MESA/lib/d3d/d3dadapter9.so.1
```

**Uso**: `source /home/noob404/mesa.sh`

### mesa-steam.sh
**Path**: `linux_in_ps4/distros/mesa/mesa-steam.sh`

Wrapper para executar comandos com o Mesa customizado (usado para Steam).

**Uso**: `/home/noob404/mesa-steam.sh %command%` (no Steam como comando de inicialização)

## Scripts de Build da Distro Consolidada e Payloads

### build_latest_distro.sh
**Path**: `linux_in_ps4/consolidado/build_latest_distro.sh`

Script que constrói a distro Arch Linux consolidada para PS4, utilizando por padrão o **Kernel Strawberry 7.0 (Bleeding Edge)**. Executa:
1. Prepara rootfs a partir do arch_minimal.tar (com verificação preventiva de desmontagem para proteger a máquina host).
2. Copia drivers Mesa customizados (se disponíveis).
3. Configura pacman.conf (IgnorePkg, DisableSandbox).
4. Copia o kernel selecionado para `/boot/vmlinuz-linux-ps4`.
5. Executa chroot via `arch-chroot` para configuração interna (rede estática `192.168.6.130/24`, fuso horário, locales, Chaotic-AUR, usuário ps4, swapfile 8GB, e gera o initramfs de forma segura).
6. Compacta todo o rootfs em `arch_ps4_consolidado.tar.xz` e gera os arquivos de boot (`bzImage`, `initramfs.cpio.gz`, `bootargs.txt`).

**Uso**: `sudo ./build_latest_distro.sh [kernel_source] [base_tarball]`
* `kernel_source`: `strawberry` (padrão, utiliza a versão pré-compilada em `kernels/strawberry-7.0/bzImage`), `neocine` (kernel 5.4.247) ou caminho direto para um arquivo `bzImage` customizado.
* `base_tarball`: caminho para o arquivo `.tar` com o rootfs do Arch Linux (padrão: `../distros/arch_minimal/arch_minimal.tar`).

### build_payloads.sh
**Path**: `linux_in_ps4/consolidado/build_payloads.sh`

Script de compilação isolado que constrói de forma independente os payloads Linux AIO para o PS4 a partir dos códigos-fonte.
1. Valida se o compilador `gcc` e o gerenciador de compilação `make` estão instalados no host.
2. Limpa construções anteriores.
3. Compila todos os payloads AIO em paralelo (`-j$(nproc)`).
4. Copia os binários compilados (`.bin` e `.elf`) para a pasta `./payload_output/`.

**Uso**: `./build_payloads.sh`
