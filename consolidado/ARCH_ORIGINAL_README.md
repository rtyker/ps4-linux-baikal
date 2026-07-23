Arch-minimal (funcional)
***Funcinou para instalar um archlinux mínimo e ir adicionando coisas.
   Cheguei até a instalar um XORG com XFCE
***

***Observações diversas
- Pode usar payload 4GB (preferencial)
- testei na tv com payload 1GB (deu boot rapido) porém teve erros de boot
- testei na tv com payload 2GB, NÃO deu boot
- testei na tv com payload 3GB, deu boot
- testei na tv com payload 4GB, deu boot

https://ps4linux.com/forums/d/413-archlinux-minimal

login: root pass: ps4l
ps4lnux pass: ps4linux

- Antes de mais nada edite o arqwuivo /etc/pacman.conf
DisableSandbox

- Configurar o usuario ps4
useradd -m -s /bin/bash ps4
echo "ps4:ps4" | chpasswd
usermod -aG wheel,audio,video,input,storage,network,lp,sys ps4
loginctl enable-linger ps4
chown -R ps4:ps4 /home/ps4

# Ajustar a internet totalmente manual
ip link set wlan0 up
dmesg | grep -i wlan
wpa_passphrase "SEU_SSID" "SUA_SENHA" > /etc/wpa_supplicant.conf
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
dhcpcd wlan0
ping 8.8.8.8

pacman -S nano vim vi
pacman -S wpa_supplicant iw

iw dev wlan0 set power_save off

ip addr add 192.168.6.1/24 dev wlan0
ip route add default via 192.168.6.1
echo "nameserver 8.8.8.8" > /etc/resolv.conf


nano /etc/wpa_supplicant/wpa_supplicant-wlan0.conf

```
ctrl_interface=/run/wpa_supplicant
update_config=1

network={
    ssid="prfelicidade_5G"
    psk="9911121314"
    key_mgmt=WPA-PSK
    proto=RSN
    pairwise=CCMP
    group=CCMP
}
```

systemctl enable wpa_supplicant@wlan0

nano /etc/resolv.conf
nameserver 8.8.8.8
nameserver 1.1.1.1

nano /etc/systemd/network/20-wlan.network
```
[Match]
Name=wlan0

[Network]
Address=192.168.6.130/24
Gateway=192.168.6.1
DNS=8.8.8.8
DNS=1.1.1.1
```

ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl enable systemd-resolved
systemctl start systemd-resolved

- Ajustar o pacman
sudo pacman -Sy archlinux-keyring
sudo pacman-key --init
sudo pacman-key --populate archlinux
sudo pacman-key --refresh-keys

sudo pacman-key --refresh-keys


- Configurar swap
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap defaults 0 0' | sudo tee -a /etc/fstab
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
sudo sysctl -p /etc/sysctl.d/99-swappiness.conf
free -h

## Git para atualizar driver e dicas
https://github.com/centi07/arch-ps4-aur


- não testei esse comando ainda

pacman -S libretro-core-info
update fix
sudo pacman -Rdd linux-firmware
sudo pacman -Syu linux-firmware
x11 fix
sudo pacman -Syu plasma-x11-session