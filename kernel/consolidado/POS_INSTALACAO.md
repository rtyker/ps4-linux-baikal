# Guia de Pós-Instalação do PS4 Linux

## Configuração Inicial

### 1. Timezone e Hora

```bash
sudo timedatectl set-timezone America/Sao_Paulo
sudo timedatectl set-ntp true
sudo timedatectl set-local-rtc 0
sudo ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
```

### 2. Locale (pt_BR)

```bash
sudo loadkeys br-abnt2
sudo bash -c 'echo -e "en_US.UTF-8 UTF-8\npt_BR.UTF-8 UTF-8" > /etc/locale.gen'
sudo locale-gen
sudo localectl set-locale LANG=pt_BR.UTF-8
echo LANG=pt_BR.UTF-8 | sudo tee /etc/locale.conf
echo KEYMAP=br-abnt2 | sudo tee /etc/vconsole.conf
setxkbmap br abnt2
```

### 3. Swap (OBRIGATÓRIO)

O PS4 tem pouca RAM disponível (cerca de 4-5GB para o Linux), então swap é essencial:

```bash
# Swap de 8GB:
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap defaults 0 0' | sudo tee -a /etc/fstab
sudo sysctl vm.swappiness=90
echo 'vm.swappiness=90' | sudo tee /etc/sysctl.d/99-swappiness.conf
```

Para sistemas com mais necessidade:
```bash
sudo dd if=/dev/zero of=/swapfile bs=1M count=12288 status=progress  # 12GB
```

### 4. Reset do Pacman (antes de atualizar)

```bash
# Comente o community se houver problemas:
# [community]
# Include = /etc/pacman.d/mirrorlist

sudo rm -rf /var/lib/pacman/sync/*
sudo rm -rf /etc/pacman.d/gnupg
sudo pacman-key --init
sudo pacman-key --populate archlinux
sudo pacman-key --populate chaotic  # se tiver chaotic-aur

sudo pacman -Syyuu --overwrite '*'
```

### 5. Configurar Chaotic-AUR (se não existir)

```bash
sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 3056513887B78AEB
sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
```

Adicione ao `/etc/pacman.conf`:
```
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
```

### 6. Drivers Gráficos Mesa/Vulkan

```bash
sudo pacman -S mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
```

### 7. Mesa Customizado (noob404)

```bash
sudo mkdir -p /home/noob404 && sudo chmod -R ugo+rw /home/noob404
wget https://github.com/noob404yt/ps4-custom-mesa-archlinux/releases/download/v1/custom-mesa-arch-v1-ps4linux.tar.xz
tar -xvf custom-mesa-arch-v1-ps4linux.tar.xz -C /home/noob404
source /home/noob404/mesa.sh
vulkaninfo | grep driverInfo
```

Para usar com Steam: `/home/noob404/mesa-steam.sh %command%`

### 8. Pacotes Adicionais

```bash
sudo pacman -S steam joystick retroarch network-manager-applet polkit-gnome
sudo pacman -S krfb  # acesso remoto KDE
sudo pacman -S openbox obconf tint2 lxappearance picom
```

## Script Automatizado de Pós-Instalação

Use o script `pos_install.sh` que automatiza todos os passos acima:

```bash
sudo ./pos_install.sh
```

O script executa:
1. Configuração de tempo
2. Configuração de locale
3. Configuração de swap
4. Verificação da idade da distro
5. Reset do banco do pacman
6. Atualização do sistema
7. Configuração Mesa/Vulkan
8. Mesa customizado (opcional)
9. Pacotes adicionais
10. Verificação final

## Configuração de Rede

### Rede Wi-Fi manual

```bash
# Scan de redes
iw dev wlan0 scan | grep SSID

# Conectar via wpa_supplicant
wpa_passphrase "SEU_SSID" "SUA_SENHA" > /etc/wpa_supplicant.conf
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
dhcpcd wlan0

# Configuração estática
ip addr add 192.168.6.130/24 dev wlan0
ip route add default via 192.168.6.1
echo "nameserver 8.8.8.8" > /etc/resolv.conf
```

### Configuração estática via systemd-network

```bash
# /etc/systemd/network/20-wlan.network
[Match]
Name=wlan0

[Network]
Address=192.168.6.130/24
Gateway=192.168.6.1
DNS=8.8.8.8
DNS=1.1.1.1
```

### Configuração de Rede no Consolidado

A distro consolidada já tem rede configurada:
- IP estático: 192.168.6.150/24
- Gateway: 192.168.6.1
- DNS: 8.8.8.8

## Version Pinning (Fixar Versões)

Use `fix_versions.sh` para evitar que atualizações quebrem o sistema:

```bash
sudo ./fix_versions.sh
```

Isso cria:
- `/etc/pacman.conf.d/ps4-version-pinning.conf` - Fixa kernel e drivers
- `/etc/pacman.conf.d/ps4-blacklist.conf` - Blacklist de pacotes problemáticos
- `/usr/local/bin/ps4-safe-update` - Script de atualização segura
- `/usr/local/bin/ps4-backup-kernel` - Script de backup do kernel

## Otimizações para Gaming

### Parâmetros de inicialização de jogos Steam

```bash
# Overwatch (funcionou com Proton 8.0, lento):
RADV_PERFTEST=gpl DXVK_STATE_CACHE=1 DXVK_ASYNC=1 gamemoderun %command%

# Age of Empires:
PROTON_USE_WINED3D=1 %command%

# Configuração geral recomendada:
RADV_PERFTEST=gpl DXVK_STATE_CACHE=1 DXVK_ASYNC=1 gamemoderun %command%
```

### Proton GE
```bash
yay -S protonup-qt
# Use Proton 8.0 para melhor compatibilidade
```

## Verificação do Sistema

```bash
sudo ./verify_installation.sh
```

O script verifica:
- Informações do sistema
- Configuração de tempo
- Configuração de locale
- Configuração de swap
- Uso do disco
- Gerenciamento de pacotes
- Drivers gráficos
- Configuração de rede
- Usuários
