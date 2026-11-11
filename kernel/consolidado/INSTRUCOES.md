# Dados do meu PS4
SouthBridge Baikal B1 0x30201
versão do firmware 12.52

- Usar o app Payload Guest que foi instalado pela loja, geralmente 3GB
- Várias distros só funcionan na TV (não funcionam no monitor)
- SEMPRE ao gravar uma imagem, certifique-se que não teve nenhum erro de gravação,
se teve, formate e regrave, não adianta insistir
- Tem muita das vezes que o problema é simplesmente cabo de HD

- Canal oficial
https://www.youtube.com/@ps4linux

- Repositório dos payloads (v24+ firmware agnóstico)
https://github.com/ps4-linux/ps4-linux-loader

- link para o kernel 5.4 Baikal
https://github.com/feeRnt/ps4-linux-12xx/releases/tag/v5.4.247__neocine-1.1

- Kernel 7.0 Strawberry para Baikal (recomendado)
https://github.com/rmuxnet/linux (branch baikal/7.0.8-Stable)

- Tutorial para extrair chaves do hdd
https://www.youtube.com/watch?v=xcPEjxGHoE4

- Site com tutoriais e imagens
https://ps4linux.com/

- Distros aqui
https://ps4linux.com/downloads/
https://ps4linux.com/forums/t/ps4-linux-releases

- Testando esse tutorial
https://github.com/hippie68/psxitarch-how-to?tab=readme-ov-file

### Tutorial do warfare

*Ajustes gerais*
- desabilitar o HDCP
- desabilitar o modo de aprimoramento
- Resolução -> 1080p
- Gama RGB -> Completa
- HDR -> Desligado
- Saída de cor intensa -> Desligado

#### Montando aqui um roteiro simples

1 - Formate o sda1 como fat32 50MB | sda2 ext4
2 - copie os tres arquivos pro sda1 => bzImage, initramfs.cpio.gz, bootlog.txt
3 - monte a partição root e grave a distro usando o tar
4 - copiar o arquivos para o ext4 /dev/sda2
5 - carregar o payload via payloadGuest

***Isso aqui abaixo funcionou, pode virar um script depois***
- Cria duas partições boot e root (psxitarch)
```
sudo fdisk /dev/sda
o
n
p
1
Enter
+50M
t
b
a
1
n
p
2
Enter
Enter
w
```
- Fomata as partições boot e root
```
sudo mkfs.vfat -F 32 /dev/sda1
sudo mkfs.ext4 -L psxitarch /dev/sda2
```
- Cria os diretorios para montar 
```
sudo mkdir -p /mnt/boot
sudo mkdir -p /mnt/root
```

- Monta os diretorios
```
sudo mount /dev/sda2 /mnt/boot
sudo mount /dev/sda2 /mnt/root
```

- Copia os dados para o kernel e iniram
```
cd /mnt/t/downloads/PS4/linux_in_ps4/distros/
sudo cp bootargs.txt bzImage initramfs.cpio.gz /mnt/boot/
sync
```
- Copia o conteudo do root, por exemplo
```
sudo tar -xvpf arch_minimal.tar -C /mnt/root --numeric-owner 
```

- Desmonta tudo
sudo umount /mnt/boot
sudo umount /mnt/root

sudo umount /mnt/root
sudo mkfs.ext4 -L psxitarch /dev/sdb2
sudo mount /dev/sdb2 /mnt/root
sudo tar -xvpf arch_minimal_v2.tar -C /mnt/root --numeric-owner 
sudo umount /mnt/root

**Retestando em ordem**
sudo tar -xvJpf Steam4PS.tar.xz -C /mnt/root --numeric-owner
sudo tar -xvpf arch_minimal.tar -C /mnt/root --numeric-owner #se for só .tar
sudo tar -xvJpf arch_minimal.tar.xz -C /mnt/root --numeric-owner #se for tar.xz comprimido
sudo tar -xvJpf psxitarch_v3.1-ITm.tar.xz -C /mnt/root --numeric-owner

- testando ainda... 01/03/2026
sudo tar -xvJpf batocera_ps4linux_40.tar.xz -C /mnt/root --numeric-owner
sudo tar -xvf "cachyos final fantasy v2.tar" -C /mnt/root --numeric-owner
sudo tar -xvJpf Steam4PS.tar.xz -C /mnt/root --numeric-owner
sudo tar -xvJpf winesapos_ps4linux.tar.xz -C /mnt/root --numeric-owner
sudo tar -xvJpf "garuda rc1.tar.xz" -C /mnt/root --numeric-owner
sudo tar -xvJpf psxitarch_v3.1-ITm.tar.xz -C /mnt/root --numeric-owner

sudo umount /mnt/boot
sudo umount /mnt/root

https://ps4linux.com/ps4-linux-documentation-aio/#PS4_Linux_Kernel_FAQ
https://ps4linux.com/run-ps4-linux-without-installing/
https://youtu.be/zaBHxAgdHUA?si=GckY4rdADNeq9x79
https://www.psx-place.com/threads/tutorial-hdd-mounting-and-decryption-on-linux.42314/

# Pagina com bons tutoriais
https://dionkill.github.io/ps4-linux-tutorial/files.html

# o Arch mínimo foi baixado de  
https://ps4linux.com/forums/d/413-archlinux-minimal

This is minimal install with my repository and without DE or WM.
root pass: ps4l
ps4lnux pass: ps4linux

https://github.com/centi07/arch-ps4-aur
Also packages can be built without a repository using aur

# Ler isso depois
https://ps4linux.com/forums/d/252-batocera-40-for-ps4-installation-setup-tutorial

# Verificar
https://ps4linux.com/downloads/

- Testes gerais

## Distros que eu testei RESULTADOS DE TSTE

### Steam4PS
até funcionou com 4GB, só atualizou depois do relogio ajustado (talvez testar mais depois)
achei muito bugada e trabalhosa de configurar, desisti

### arch_minimal 
- gravei simples da primeira vez, testei com payload de 3gb, não subiu imagem no monitor do pc

funcionou com payload 4GB, como o nome diz, vem "seco" tem que instalar
tudo na mão. É bom para aprendizado, mas não é pratico para instalar

### psxitarch-v2 - não abriu xorg não compensa testar, versão antiga

### Batocera40
funcionou muito bem, tem kodi e emuladores, é mais embarcado

### CachyOS 
até agora o melhor visualmente com kde
tudo funcionou, só ocupa muito espaço
o HD de 120GB não foi suficiente para testar o overwatch

### psxitarch3.1-unoficial - acho que é o escolhido
- Interface simples
- Gostei do autologin
- Interface leve lxde
- **FANTÁSTICO** o script de montagem de HD Interno
- usuario psxita senha changeit

## Guia geral de instalação
*O guia abaixo é genérico, existem distros que possuem coisas específicas*

- Particionar
Crie duas partições no disco
sda1 => 50M fat32, aqui vai o bzImage e o inicpio
sda2 => restante do disco ext4, é o root do sistema

- copiar o bzImage, boot_log.txt
- usar o método de copiar já descompactado para o pendrive
- usar o payload de 3gb

## Instruções pós instalação
sudo timedatectl set-timezone America/Sao_Paulo
sudo timedatectl set-ntp true
sudo timedatectl set-local-rtc 0

- criar e ajustar a swap
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap defaults 0 0' | sudo tee -a /etc/fstab
sudo sysctl vm.swappiness=80
echo 'vm.swappiness=80' | sudo tee /etc/sysctl.d/99-swappiness.conf

- Esse comando me ajudou ver a idade da distro
ls -ld /
https://ps4linux.com/steamos-3-ps4-nazky/

# Instruções para corrigir / atualizar o mesa para VULKAN
 https://ps4linux.com/ps4-pro-fix-vulkan-fix-crash/
 https://github.com/noob404yt/ps4-custom-mesa-archlinux
 https://youtu.be/8P0s63DyiEM?si=koxl0iUR1kLzbjar

 - baixar o tar.xz e os scripts .sh
 - criar a pasta 
 sudo mkdir -p /home/noob404 && sudo chmod -R ugo+rw /home/noob404 
tar -xvf custom-mesa-arch-v1-ps4linux.tar.xz -C /home/noob404
source /home/noob404/mesa.sh
- testar
vulkaninfo | grep driverInfo
/home/noob404/mesa-steam.sh %command%

 ## Coisas que corrigi depois dos sistema instalado
- TEM que ajustar o mesa
 sudo pacman -S mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
 sudo pacman -S vulkan-radeon lib32-vulkan-radeon

1 - Ter certeza que o relógio está ok
timedatectl
sudo timedatectl set-timezone America/Sao_Paulo
sudo timedatectl set-ntp true
sudo ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

2 - Ajustar o locale
sudo loadkeys br-abnt2
sudo bash -c 'echo -e "en_US.UTF-8 UTF-8\npt_BR.UTF-8 UTF-8" > /etc/locale.gen'
sudo locale-gen
sudo localectl set-locale LANG=pt_BR.UTF-8
echo LANG=pt_BR.UTF-8 | sudo tee /etc/locale.conf

sudo nano /etc/vconsole.conf
KEYMAP=br-abnt2
setxkbmap br abnt2

3 - Ajustar o swap é obrigatorio
sudo swapoff -a
swapon --show
sudo dd if=/dev/zero of=/swapfile bs=1M count=12288 status=progress
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
free -h
sudo sysctl vm.swappiness=90
echo 'vm.swappiness=90' | sudo tee /etc/sysctl.d/99-swappiness.conf

- Rodar isso antes de atualizar o sistema, principalmente se tiver problemas com pacman
essa é uma operação um pouco demorada
```
- comente o community
[community]
Include = /etc/pacman.d/mirrorlist

sudo rm -rf /var/lib/pacman/sync/*
sudo rm -rf /etc/pacman.d/gnupg
sudo pacman-key --init
sudo pacman-key --populate archlinux
sudo pacman-key --populate chaotic
- se for cachyos
```
sudo pacman-key --populate cachyos
sudo pacman -Syy cachyos-keyring
```

sudo pacman -Syy archlinux-keyring chaotic-keyring --overwrite '*'


sudo pacman -Scc

```

## Tem distro que não tem o chaotic
sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 3056513887B78AEB

sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

-adicione o mirror
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist

- Em algumas distros tem que usar o --disable-sandbox no pacman

*um upgrade pode SEMPRE ter a possibilidade de quebrar o sistema*
- tive que remover alguns pacotes para depois instalar denovo
```
sudo pacman -Syyuu --overwrite '*'
foram +- 861 pacotes atualizados
```

### Trecho à parte para upgrade do psxita
- rodar antes de atualizar com Syu
*Desativa a checagem de chaves gpg*
sudo sed -i 's/SigLevel = Required DatabaseOptional/SigLevel = Never/g' /etc/pacman.conf

sudo pacman -Rdd rest libfm-gtk2 jdk jre
sudo pacman -S glibc lib32-glibc
sudo pacman -S xdg-desktop-portal-gtk

*SOMENTE* Se tudo quebrar e ficar em um estado que o pacman não funcionar
```
cd /tmp
curl -L -O https://archive.archlinux.org/packages/g/gcc-libs/gcc-libs-13.2.1-6-x86_64.pkg.tar.zst

zstd -d gcc-libs-13.2.1-6-x86_64.pkg.tar.zst -c | \
tar -xvf - usr/lib/libgcc_s.so.1

cp usr/lib/libgcc_s.so.1 /usr/lib/
ln -sf libgcc_s.so.1 /usr/lib/libgcc_s.so


pacstrap -K /mnt/root base glibc gcc-libs gcc
pacman -Syy
pacman -S gcc gcc-libs lib32-gcc-libs glibc --overwrite '*'
pacman -Syu

```

- se tudo funcionar depois do upgrade, algumas coisas "somem"
sudo pacman -S network-manager-applet
sudo pacman -S lib32-llvm-libs lib32-mesa lib32-vulkan-radeon

- Coisas que instalei
sudo pacman -S steam joystick  
sudo pacman -S retroarch
sudo pacman -S krfb # acesso remoto KDE

- Pra jogar o Age of empires
PROTON_USE_WINED3D=1 %command%

- chat recomendou isso ainda estou testando
# ativa compilação asíncrona de shaders
DXVK_ASYNC=1 %command% ou gamemoderun %command%
RADV_PERFTEST=gpl DXVK_STATE_CACHE=1 DXVK_ASYNC=1 gamemoderun %command%

RADV_PERFTEST=gpl: usa otimizações extras no driver RADV (para AMD)
DXVK_STATE_CACHE=1: acelera recompilação de shaders
DXVK_ASYNC=1: melhora processamento gráfico paralelo
gamemoderun: seta perfil de desempenho no sistema

sudo pacman -S openbox obconf tint2 lxappearance picom
sudo pacman -S network-manager-applet polkit-gnome gvfs
sudo pacman -S arc-gtk-theme

pkill Xorg
pkill openbox
pkill jwm

# limpa o cache do steam
rm -rf ~/.local/share/Steam/ubuntu12_32/steam-runtime

tail -f ~/.steam/steam/logs/proton_log.txt

#overwatch funcionou com proton 8.0
yay -S protonup-qt

-- esse funcionou...
pkill -9 -f steam
rm -rf ~/.local/share/Steam/steamapps/shadercache/2357570
rm -rf ~/.local/share/Steam/steamapps/compatdata/2357570


RADV_PERFTEST=gpl DXVK_STATE_CACHE=1 DXVK_ASYNC=1 gamemoderun %command%
PROTON_HIDE_NVIDIA_GPU=0 DXVK_ASYNC=1 RADV_PERFTEST=aco %command%
RADV_PERFTEST=aco DXVK_ASYNC=1 %command%
pki

RESUMO ATÉ AQUI, 
funcionou com proton 8, ficou lento, sem parametros nenhum
verificar depois com cada parametro

com proton 10 ficou compilando os shaders....

/context
/clear
/compact


chpserver 	 | 201.76.28.10      | 192.168.0.19         | 84:34:97:03:BC:8E
oralinux (oravm) | 201.76.28.10:2323 | 192.168.0.109:10001  | usuario oracle senha: Qqr****** | estático
desenv2  	 | 201.76.28.10:3397 | 192.168.0.110:10002  | usuário vr1  senha: aw3123 
vmversoes        | 201.76.28.10:3395 | 192.168.0.108:10003  | usuário vr1  senha #aw3$se4
jedivm  	 |                   | 192.168.0.107:10004  | JEDIVM (interno)    senha Qqr****  
oraclejedi       | 201.76.28.10:3400 | 192.168.0.111:10005  | 08-00-27-AB-69-A7   usuario administrador senha do banco Qqr***** senha da máquina #aw3$se4



porta 2323
3397
3395
3400
3000

Porta principal do TS do sevidor -> 192.168.0.19:3389
Porta do SSH do servidor 22