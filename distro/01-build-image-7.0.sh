#!/bin/bash
# 01-build-image-7.0.sh — Cria rootfs Arch + initramfs para kernel 7.0 Strawberry Baikal
#
# Uso:
#   sudo ./01-build-image-7.0.sh <TAG>                  # build limpo (rm -rf do BUILD_ROOT)
#   sudo ./01-build-image-7.0.sh <TAG> --incremental    # reutiliza o rootfs já construído
#
# --incremental existe porque a maioria do desenvolvimento é de kernel/drivers:
# quando só o bzImage muda, o rootfs não precisa ser recriado do zero (pula
# rm -rf + pacstrap e vai direto para configuração + mkinitcpio + tarball).
# Exige um rootfs válido em $ROOTFS_DIR (falha alta se não existir).
set -euo pipefail

[ "$EUID" -eq 0 ] || { echo "Execute com sudo"; exit 1; }

# GUARD: este script depende de pacstrap/pacman/arch-chroot (ferramentas Arch).
# Em hosts sem Arch (Debian, Ubuntu, etc.) o pacman não existe e o build morre
# depois de baixar centenas de MB. Use o wrapper Docker:
#   ./scripts/build-image-docker.sh <TAG>
command -v pacman >/dev/null 2>&1 || {
  echo "❌ ERRO FATAL: 'pacman' não encontrado no host."
  echo ""
  echo "  Este script requer um host Arch Linux (pacstrap, pacman, arch-chroot)."
  echo "  Em hosts sem Arch (Debian, Ubuntu, etc.) use o wrapper Docker:"
  echo ""
  echo "      cd distro && ./scripts/build-image-docker.sh <TAG>"
  echo ""
  echo "  Ou instale Arch e rode diretamente:"
  echo "      sudo $0 <TAG>"
  echo ""
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="${PS4_BUILD_ROOT:-/mnt/hdauxiliar/temp/arch_build_7.0}"
# Artefatos de boot (bzImage/config/bootargs/initramfs) são produzidos pelo build da
# FRENTE 1 (kernel/00-build-kernel-7.0.sh) mas gravados AQUI, em distro/boot_referencia/
# — pasta única, nunca duplicada. Sobrescreva com PS4_BOOT_REF=... para apontar
# para outro conjunto de artefatos.
BOOT_DIR="${PS4_BOOT_REF:-$SCRIPT_DIR/boot_referencia}"

ROOTFS_DIR="$BUILD_ROOT/rootfs"

# TAG: a mesma tag do build do kernel. Todo artefato é lido/gravado POR TAG
# (contrato que deploy-boot-7.0.sh e promote-release.sh exigem: 4 arquivos
# bzImage-7.0-<TAG>, config-7.0-<TAG>, bootargs-7.0-<TAG>.txt,
# initramfs-7.0-<TAG>.cpio.gz). Sem TAG, autodetecta apenas se houver
# exatamente uma tag disponível — nunca escolhe no escuro.
TAG="${1:-}"
INCREMENTAL="${2:-}"
if [ -z "$TAG" ]; then
  mapfile -t _TAGS < <(cd "$BOOT_DIR" 2>/dev/null && ls -1 bzImage-7.0-* 2>/dev/null | sed 's/^bzImage-7\.0-//')
  case "${#_TAGS[@]}" in
    0)
      echo "ERRO: nenhuma tag em $BOOT_DIR (nenhum bzImage-7.0-*) e nenhum TAG informado."
      echo "      Rode antes: sudo ../kernel/00-build-kernel-7.0.sh <TAG>"
      exit 1 ;;
    1)
      TAG="${_TAGS[0]}"
      echo "=== TAG autodetectada: $TAG ===" ;;
    *)
      echo "ERRO: há ${#_TAGS[@]} tags em $BOOT_DIR — diga qual usar:"
      printf '  %s\n' "${_TAGS[@]}"
      echo "Uso: sudo $0 <TAG> [--incremental]"
      exit 1 ;;
  esac
fi

if [ "$INCREMENTAL" = "--incremental" ]; then
  INCREMENTAL=1
else
  INCREMENTAL=0
fi

BZIMAGE="$BOOT_DIR/bzImage-7.0-$TAG"
CONFIG="$BOOT_DIR/config-7.0-$TAG"
BOOTARGS_OUT="$BOOT_DIR/bootargs-7.0-$TAG.txt"
INITRAMFS_OUT="$BOOT_DIR/initramfs-7.0-$TAG.cpio.gz"

[ -f "$BZIMAGE" ] || { echo "ERRO: $BZIMAGE não encontrado"; exit 1; }
[ -f "$CONFIG" ]  || { echo "ERRO: $CONFIG não encontrado"; exit 1; }

# Verifique se o BUILD_ROOT suporta chroot/mount (regra do AGENTS.md).
case "$BUILD_ROOT" in
  /mnt/t|/mnt/t/*)
    echo "AVISO: BUILD_ROOT em $BUILD_ROOT — verifique se suporta chroot/mount."
    ;;
esac

# Robust cleanup function - handles "device or resource busy" by unmounting first
cleanup() {
  set +e
  if [ -d "$BUILD_ROOT" ]; then
    # Unmount all mounts under BUILD_ROOT recursively (deepest first)
    findmnt -R "$BUILD_ROOT" -n -o TARGET 2>/dev/null | sort -r | while read -r mp; do
      mountpoint -q "$mp" && umount -l "$mp" 2>/dev/null || true
    done
  fi
  # Also clean standard chroot mounts
  for mp in proc sys dev run; do
    mountpoint -q "$ROOTFS_DIR/$mp" 2>/dev/null && umount -R "$ROOTFS_DIR/$mp" 2>/dev/null || true
  done
  # Unmount pacman cache
  mountpoint -q "$ROOTFS_DIR/var/cache/pacman/pkg" 2>/dev/null && umount -l "$ROOTFS_DIR/var/cache/pacman/pkg" 2>/dev/null || true
  sleep 0.5
  set -e
}
trap cleanup EXIT INT TERM

# Determinar versão do kernel 7.0 (UTS_RELEASE real)
# O UTS_RELEASE é a string exata usada por modules_install e mkinitcpio
KERNEL_BUILD_DIR="$SCRIPT_DIR/../kernel/kernel_build_7.0"
UTS_RELEASE_FILE="$KERNEL_BUILD_DIR/include/generated/utsrelease.h"
if [ -f "$UTS_RELEASE_FILE" ]; then
  KVER_FULL=$(grep -oP '"\K[^"]+' "$UTS_RELEASE_FILE")
elif [ -f "$CONFIG" ]; then
  KVER=$(grep "^KERNEL_VERSION" "$CONFIG" | cut -d= -f2 2>/dev/null || echo "7.0.8")
  LOCALVERSION=$(grep "^CONFIG_LOCALVERSION=" "$CONFIG" | sed 's/^CONFIG_LOCALVERSION="//' | sed 's/"$//' 2>/dev/null)
  KVER_FULL="${KVER}${LOCALVERSION}"
else
  echo "ERRO: Não foi possível determinar versão do kernel 7.0"
  exit 1
fi

echo "=== Kernel version: $KVER_FULL ==="

MODULES_DIR="$ROOTFS_DIR/lib/modules/$KVER_FULL"
OUTPUT_TAR="$SCRIPT_DIR/arch_minimal_v2-7.0.tar"

echo "=== Preparando diretórios ==="
cleanup
if [ "$INCREMENTAL" = "1" ]; then
  echo "=== Modo incremental: reutilizando rootfs existente em $ROOTFS_DIR ==="
  # Falha alta: incremental sem rootfs válido não pode "seguir como se nada"
  # (fallback silencioso em ferramenta de build é armadilha).
  if [ ! -x "$ROOTFS_DIR/usr/bin/pacman" ]; then
    echo "ERRO: modo incremental exige um rootfs já construído em $ROOTFS_DIR"
    echo "      (não encontrei $ROOTFS_DIR/usr/bin/pacman)."
    echo "      Rode uma vez SEM --incremental para criar o rootfs do zero."
    exit 1
  fi
  mkdir -p "$ROOTFS_DIR" "$BOOT_DIR"
else
  rm -rf "$BUILD_ROOT"
  mkdir -p "$ROOTFS_DIR" "$BOOT_DIR"

  echo "=== Bootstrap Arch Linux base ==="
  pacstrap -c "$ROOTFS_DIR" base linux-api-headers --noconfirm
fi

# Montar cache do pacman no chroot
mkdir -p "$ROOTFS_DIR/var/cache/pacman/pkg"
mount --bind /var/cache/pacman/pkg "$ROOTFS_DIR/var/cache/pacman/pkg"

echo "=== Configurando pacman.conf (systemd 258 pin, DisableSandbox) ==="
cat > "$ROOTFS_DIR/etc/pacman.conf" << 'PACMANEOF'
[options]
HoldPkg     = pacman glibc
Architecture = auto
Color
CheckSpace
ParallelDownloads = 5
DisableSandbox
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional
IgnorePkg   = linux linux-headers mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
PACMANEOF

echo "=== Instalando pacotes essenciais ==="
# Pacotes gráficos (xorg/mesa/vulkan/openbox) ficam disponíveis na imagem,
# mas NÃO sobem sozinhos: nenhum display manager é instalado/habilitado e
# systemctl set-default abaixo força multi-user.target (boot em TTY puro).
# Rodar Xorg/openbox fica manual (startx) até a distro estar completa.
PKGS=(
  base
  linux-firmware
  openssh
  sudo
  vim
  nano
  htop
  iotop
  iftop
  nethogs
  net-tools
  iproute2
  dhcpcd
  wpa_supplicant
  wireless-regdb
  iw
  bluez
  bluez-utils
  usbutils
  pciutils
  lsof
  strace
  perf
  dmidecode
  smartmontools
  nvme-cli
  mdadm
  lvm2
  cryptsetup
  sleuthkit
  btrfs-progs
  dosfstools
  e2fsprogs
  xfsprogs
  f2fs-tools
  ntfs-3g
  exfatprogs
  samba
  nfs-utils
  cronie
  systemd-sysvcompat
  python3
  python-pip
  git
  curl
  wget
  rsync
  unzip
  tar
  gzip
  xz
  zstd
  jq
  ccache
  distcc
  meson
  ninja
  pkgconf
  mkinitcpio
  mesa
  lib32-mesa
  vulkan-radeon
  lib32-vulkan-radeon
  vulkan-tools
  mesa-utils
  xorg-server
  xorg-xinit
  openbox
)

# Instalar usando pacman do host (evita problema de mountpoint no chroot)
HOST_PACMAN_CONF="$ROOTFS_DIR/etc/pacman.conf"
HOST_PACMAN_CACHE="/var/cache/pacman/pkg"
mkdir -p "$ROOTFS_DIR/var/lib/pacman/sync"

# Montar /proc necessário para hooks pós-transação do pacman (systemd-tmpfiles etc.)
mount -t proc proc "$ROOTFS_DIR/proc"

pacman --root "$ROOTFS_DIR" --config "$HOST_PACMAN_CONF" --cachedir "$HOST_PACMAN_CACHE" -Sy --noconfirm "${PKGS[@]}"

umount "$ROOTFS_DIR/proc"

echo "=== Configurando sistema ==="

# Timezone
ln -sf /usr/share/zoneinfo/America/Sao_Paulo "$ROOTFS_DIR/etc/localtime"

# Locale (paridade com o rootfs 5.4 - en_US + pt_BR)
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$ROOTFS_DIR/etc/locale.gen"
sed -i 's/^#pt_BR.UTF-8 UTF-8/pt_BR.UTF-8 UTF-8/' "$ROOTFS_DIR/etc/locale.gen"
arch-chroot "$ROOTFS_DIR" locale-gen
echo "LANG=pt_BR.UTF-8" > "$ROOTFS_DIR/etc/locale.conf"
echo "KEYMAP=br-abnt2" > "$ROOTFS_DIR/etc/vconsole.conf"

# Hostname
echo "ps4-baikal" > "$ROOTFS_DIR/etc/hostname"

# Hosts
cat > "$ROOTFS_DIR/etc/hosts" << 'HOSTSEOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   ps4-baikal.localdomain ps4-baikal
HOSTSEOF

# Rede estática (systemd-networkd)
mkdir -p "$ROOTFS_DIR/etc/systemd/network"
cat > "$ROOTFS_DIR/etc/systemd/network/20-ethernet.network" << 'NETEOF'
[Match]
Name=eth0

[Network]
Address=192.168.0.2/24
Gateway=192.168.0.1
DNS=192.168.0.1
DNS=8.8.8.8
NETEOF

# Driver Ethernet Baikal (mts.ko) — auto-carregamento DESATIVADO temporariamente (2026-11-12).
# Motivo: o probe do PHY custa ~33 s de `systemd-modules-load` no boot e a Ethernet ainda
# não tem link (PHY mudo). O módulo continua instalado no rootfs e pode ser carregado à mão
# (`modprobe mts` usa stage=4 via /etc/modprobe.d/mts.conf).
# Reativar: ENABLE_MTS=1 sudo ./01-build-image-7.0.sh <TAG>
# Ver outros/docs/BACKLOG.md, item "Auditoria de boot/otimização".
mkdir -p "$ROOTFS_DIR/etc/modprobe.d"
echo "options mts stage=4" > "$ROOTFS_DIR/etc/modprobe.d/mts.conf"
if [ "${ENABLE_MTS:-0}" = "1" ]; then
    mkdir -p "$ROOTFS_DIR/etc/modules-load.d"
    echo "mts" > "$ROOTFS_DIR/etc/modules-load.d/mts.conf"
    echo "[info] mts.ko SERA carregado no boot (ENABLE_MTS=1)."
else
    rm -f "$ROOTFS_DIR/etc/modules-load.d/mts.conf"
    echo "[info] mts.ko NAO sera carregado no boot (padrao; use ENABLE_MTS=1 para reativar)."
fi

# SSH (config permissiva, paridade com o rootfs 5.4 que funciona).
# Idempotente: usa um drop-in em sshd_config.d/ em vez de reescrever o sshd_config
# a cada build (o modelo antigo fazia `mv` + prepend, o que DUPLICAVA o bloco a cada
# execução — em 2026-11-12 o PS4 tinha o bloco duas vezes).
#
# ⚠️ PermitEmptyPasswords NUNCA pode ser "yes": o sshd tenta autenticar com senha
# vazia em TODA conexão; o pam_unix falha e o pam_faillock conta 1 falha por conexão
# (`pam_faillock(sshd:auth): authentication failure` antes do `Accepted publickey`).
# Com deny=3 (padrão do Arch) a conta trava depois de 3 logins — foi exatamente o
# que aconteceu em 2026-11-12 (banner "account is locked due to 3 failed logins").
SSHD_ETC="$ROOTFS_DIR/etc/ssh"
if [ -f "$SSHD_ETC/sshd_config" ]; then
  mkdir -p "$SSHD_ETC/sshd_config.d"
  cat > "$SSHD_ETC/sshd_config.d/00-ps4-baikal.conf" << 'SSHEOF'
# Gerado por distro/01-build-image-7.0.sh
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
StrictModes no
SSHEOF
  # Garante que o sshd_config inclua o diretório de drop-ins (Arch já inclui)
  if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' "$SSHD_ETC/sshd_config"; then
    printf '\nInclude /etc/ssh/sshd_config.d/*.conf\n' >> "$SSHD_ETC/sshd_config"
  fi
  # Remove resíduo de builds antigos (bloco duplicado com PermitEmptyPasswords yes)
  if grep -q '^PermitEmptyPasswords' "$SSHD_ETC/sshd_config"; then
    sed -i '/^PermitRootLogin /d;/^PasswordAuthentication /d;/^PermitEmptyPasswords /d;/^StrictModes /d' "$SSHD_ETC/sshd_config"
    echo "[info] removido bloco SSH legado do topo do sshd_config (agora via drop-in)."
  fi
fi
arch-chroot "$ROOTFS_DIR" ssh-keygen -A
ln -sf /usr/lib/systemd/system/sshd.service "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/sshd.service"

# Garantir que o boot padrão é multi-user.target (console text mode puro, sem interface gráfica)
echo "=== Configurando boot padrão para multi-user.target (TTY console) ==="
arch-chroot "$ROOTFS_DIR" systemctl set-default multi-user.target
echo "Boot padrão definido para multi-user.target (console text mode TTY)"

# SSH automático: nesta arquitetura o rootfs JÁ É o sistema rodando
# (root=LABEL=psxitarch no bootargs), então basta habilitar o sshd normal
# (feito acima, com sshd.service em multi-user.target.wants).
#
# NÃO copiamos mais o "ssh-startup.sh" + ssh-auto-startup.service: eles eram
# da arquitetura antiga (rootfs em /dev/sdb2, montado RO e chroot para rodar
# o sshd). Hoje esse /dev/sdb2 não existe (USB = sda, HD interno = sdb) e o
# serviço só produzia uma falha no journal e um chroot inútil.
echo "=== SSH: sshd.service habilitado (sem o chroot legado) ==="

# NOTA: NÃO precisa de serviço de netconsole aqui. CONFIG_NETCONSOLE=y é
# builtin no kernel 7.0 (não módulo) e se ativa sozinho lendo o parâmetro
# netconsole= do cmdline no early boot - não depende de systemd/userspace.
# (Um serviço rodando "nc -u -l -p 6666" DENTRO do PS4 não tem efeito algum
# sobre o netconsole do kernel - foi removido daqui por ser um resquício sem
# função, mantido só como nota para não recriarmos o mesmo engano.)

# Reduzir ruído de log (paridade com o rootfs 5.4 que funciona)
mkdir -p "$ROOTFS_DIR/etc/sysctl.d"
echo "kernel.printk = 3 4 1 7" > "$ROOTFS_DIR/etc/sysctl.d/30-loglevel.conf"
grep -q "^Audit=" "$ROOTFS_DIR/etc/systemd/journald.conf" 2>/dev/null \
  || sed -i '/^\[Journal\]/a Audit=no' "$ROOTFS_DIR/etc/systemd/journald.conf"

# Senha root
echo "root:ps4" | arch-chroot "$ROOTFS_DIR" chpasswd

# Usuario ps4 (paridade com o rootfs 5.4 que funciona)
arch-chroot "$ROOTFS_DIR" useradd -m -G wheel -s /bin/bash ps4 2>/dev/null || true
echo "ps4:ps4" | arch-chroot "$ROOTFS_DIR" chpasswd

# Sudo sem senha para root
echo "root ALL=(ALL) NOPASSWD: ALL" > "$ROOTFS_DIR/etc/sudoers.d/root-nopasswd"
chmod 440 "$ROOTFS_DIR/etc/sudoers.d/root-nopasswd"

mkdir -p "$ROOTFS_DIR/etc/sudoers.d"
echo "%wheel ALL=(ALL:ALL) ALL" > "$ROOTFS_DIR/etc/sudoers.d/wheel"
chmod 440 "$ROOTFS_DIR/etc/sudoers.d/wheel"

# WiFi (paridade com o rootfs 5.4 que funciona - mesmo SSID/senha)
echo "=== Configurando wpa_supplicant para WiFi ==="
mkdir -p "$ROOTFS_DIR/etc/wpa_supplicant"
cat > "$ROOTFS_DIR/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" << 'WPAEOF'
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel
update_config=1
country=BR

network={
	ssid="prfelicidade_5G"
	psk="9911121314"
}
WPAEOF
chmod 600 "$ROOTFS_DIR/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
mkdir -p "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/wpa_supplicant@.service \
  "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service"
mkdir -p "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/dhcpcd.service \
  "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/dhcpcd.service"
# eth0 já é estático via systemd-networkd (20-ethernet.network acima) -
# dhcpcd só deve gerenciar wlan0, senão os dois disputam a interface eth0
echo "denyinterfaces eth0" >> "$ROOTFS_DIR/etc/dhcpcd.conf"

# CORREÇÃO 2026-07-23: Habilitar systemd-networkd para carregar config de rede estática (eth0)
mkdir -p "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/systemd-networkd.service \
  "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"

# (Opcional) Habilitar systemd-resolved para DNS via systemd-networkd
ln -sf /usr/lib/systemd/system/systemd-resolved.service \
  "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/systemd-resolved.service"

echo "=== Instalando módulos do kernel 7.0 ==="
# Copiar módulos compilados do kernel build
if [ -d "$KERNEL_BUILD_DIR" ]; then
  echo "Copiando módulos pré-compilados de $KERNEL_BUILD_DIR..."
  make -C "$KERNEL_BUILD_DIR" INSTALL_MOD_PATH="$ROOTFS_DIR" INSTALL_MOD_STRIP=1 modules_install
else
  echo "AVISO: Diretório de build do kernel não encontrado. Módulos não instalados."
fi

# Copiar opcionalmente o mts.ko compilado separadamente (em drivers_mts/build/mts.ko)
MTS_LOCAL_KO="$SCRIPT_DIR/../kernel/drivers_mts/build/mts.ko"
if [ -f "$MTS_LOCAL_KO" ]; then
  MTS_DEST_DIR="$MODULES_DIR/kernel/drivers/net/ethernet/sony"
  echo "=== Sobrescrevendo/Garantindo mts.ko local mais recente de drivers_mts/build/mts.ko ==="
  mkdir -p "$MTS_DEST_DIR"
  cp -v "$MTS_LOCAL_KO" "$MTS_DEST_DIR/mts.ko"
  echo "Executando depmod para atualizar dependências de módulos..."
  arch-chroot "$ROOTFS_DIR" depmod -a "$KVER_FULL"
else
  echo "Aviso: Módulo local mts.ko não encontrado em $MTS_LOCAL_KO. Mantendo versão padrão."
fi

# --- Mesa patchado PS4 Gladius/Liverpool (correção de corrupção visual) ----
# O pacote "mesa" instalado via pacman acima (linha ~153) é o binário oficial
# do Arch, que NÃO reconhece CHIP_GLADIUS/CHIP_LIVERPOOL (ver
# consolidado/MESA_GLADIUS_LIVERPOOL_FIX.md) -- causa a corrupção visual em
# qualquer coisa renderizada via OpenGL/radeonsi (Xorg+Cinnamon, jogos, etc).
# Em vez de sobrescrever os arquivos do pacote pacman (frágil: nomes de
# arquivo dependem do sufixo de versão "-archX.Y" do build oficial, e
# "pacman -Syu" reverteria a troca), instalamos o Mesa patchado num prefixo
# próprio e apontamos o sistema pra ele via /etc/environment -- exatamente o
# método validado ao vivo em 2026-07-24 (glxinfo confirmou "gladius", sem
# AMD_DEBUG=notiling).
MESA_PATCHED_TAR="$SCRIPT_DIR/mesa/mesa-ps4-gladius-liverpool-latest.tar.xz"
echo "=== Instalando Mesa patchado PS4 Gladius/Liverpool (opcional) ==="
if [ -f "$MESA_PATCHED_TAR" ]; then
  MESA_DEST="$ROOTFS_DIR/opt/mesa-ps4-patched"
  mkdir -p "$MESA_DEST"
  tar xJf "$MESA_PATCHED_TAR" -C "$MESA_DEST"
  echo "Mesa patchado extraido para /opt/mesa-ps4-patched no rootfs."

  # Persistir via /etc/environment (lido por pam_env em todo login, inclusive
  # sessoes X/Wayland -- confirmado funcionando ao vivo 2026-07-24).
  ENV_FILE="$ROOTFS_DIR/etc/environment"
  touch "$ENV_FILE"
  grep -q '^LD_LIBRARY_PATH=' "$ENV_FILE" || \
    echo 'LD_LIBRARY_PATH=/opt/mesa-ps4-patched/lib' >> "$ENV_FILE"
  grep -q '^LIBGL_DRIVERS_PATH=' "$ENV_FILE" || \
    echo 'LIBGL_DRIVERS_PATH=/opt/mesa-ps4-patched/lib/dri' >> "$ENV_FILE"
  echo "Variaveis LD_LIBRARY_PATH/LIBGL_DRIVERS_PATH persistidas em /etc/environment."
else
  echo "AVISO: $MESA_PATCHED_TAR nao encontrado -- rode mesa/01-build-mesa.sh antes"
  echo "       desta imagem pra incluir a correcao. Prosseguindo SEM o Mesa"
  echo "       patchado (fica valendo o mesa oficial do Arch, com o bug de"
  echo "       corrupção visual conhecido em CHIP_GLADIUS/CHIP_LIVERPOOL)."
fi


# Verificar módulos essenciais para Baikal
# Formato: "nome_modulo:config_option"
# O script verifica se existe como .ko OU se está built-in (=y) no .config
# NOTA: a Ethernet do Baikal é o driver MTS (CONFIG_MTS_GBE), NÃO sky2 — o
# sky2 é do Marvell Yukon (Aeolia/Belize) e forçá-lo a sondar a GBE Baikal
# já congelou o PCIe e o vídeo (patch sky2-baikal-gbe.patch, banido em
# 2026-07-22). Aqui o sky2 aparece só como built-in inofensivo: o ID do
# dispositivo Baikal (104d:90d8) não casa com a tabela do sky2.
REQUIRED_MODULES=(
  "mt76-sdio:CONFIG_MT76_SDIO"
  "btmtksdio:CONFIG_BT_MTKSDIO"
  "amdgpu:CONFIG_DRM_AMDGPU"
  "snd-hda-intel:CONFIG_SND_HDA_INTEL"
  "mts:CONFIG_MTS_GBE"
)
# Drivers built-in (=y) no kernel 7.0 - não precisam de .ko no initramfs
BUILTIN_DRIVERS=(
  "CONFIG_SKY2"
  "CONFIG_MT76_SDIO"
  "CONFIG_USB_XHCI_HCD"
  "CONFIG_USB_XHCI_AEOLIA"
  "CONFIG_SATA_AHCI"
  "CONFIG_MMC_SDHCI"
  "CONFIG_MMC_SDHCI_PCI"
)

KERNEL_CONFIG="$KERNEL_BUILD_DIR/.config"
echo "=== Verificando módulos essenciais ==="
for entry in "${REQUIRED_MODULES[@]}"; do
  mod="${entry%%:*}"
  cfg="${entry##*:}"
  mod_file=$(find "$MODULES_DIR" -name "${mod}.ko*" 2>/dev/null | head -1 || true)
  cfg_val=$(grep "^${cfg}=" "$KERNEL_CONFIG" 2>/dev/null | head -1 || true)
  if [ -n "$mod_file" ]; then
    echo "  OK (modulo): $mod -> $(basename "$mod_file")"
  elif [ -n "$cfg_val" ]; then
    echo "  OK (built-in): $mod -> $cfg_val"
  else
    echo "  FALTANDO: $mod"
  fi
done
echo "=== Verificando drivers built-in ==="
for cfg in "${BUILTIN_DRIVERS[@]}"; do
  cfg_val=$(grep "^${cfg}=" "$KERNEL_CONFIG" 2>/dev/null | head -1 || true)
  if [ -n "$cfg_val" ]; then
    echo "  OK (built-in): $cfg_val"
  else
    echo "  FALTANDO: $cfg"
  fi
done

echo "=== Criando initramfs (mkinitcpio) ==="
# Configurar mkinitcpio para kernel 7.0 (sem autodetect para evitar remover módulos no chroot)
cat > "$ROOTFS_DIR/etc/mkinitcpio.conf" << 'MKEOF'
MODULES=(ext4 ahci sd_mod btmtksdio amdgpu snd-hda-intel mts usbhid uas usb_storage)
BINARIES=()
FILES=(/lib/firmware/edid/ps4_tv_edid.bin)
HOOKS=(base udev modconf block filesystems keyboard fsck)
COMPRESSION="gzip"
MKEOF

# Copiar EDID firmware
mkdir -p "$ROOTFS_DIR/lib/firmware/edid"
cp "$SCRIPT_DIR/ps4_tv_edid.bin" "$ROOTFS_DIR/lib/firmware/edid/ps4_tv_edid.bin"

# Copiar firmwares genuínos Gladius GPU (AMD PS4 Pro)
echo "=== Copiando firmwares genuínos AMD Gladius GPU ==="
mkdir -p "$ROOTFS_DIR/lib/firmware/amdgpu"
if [ -d "$SCRIPT_DIR/firmware_gpu/amdgpu" ]; then
  cp -v "$SCRIPT_DIR/firmware_gpu/amdgpu"/gladius_*.bin "$ROOTFS_DIR/lib/firmware/amdgpu/" || true
fi

# Copiar firmwares MediaTek MT7668 (WiFi/BT Baikal)
echo "=== Copiando firmwares MediaTek MT7668 (WiFi/BT) ==="
mkdir -p "$ROOTFS_DIR/lib/firmware/mediatek"
if [ -d "$SCRIPT_DIR/firmware_wifi/mediatek" ]; then
  cp -v "$SCRIPT_DIR/firmware_wifi/mediatek"/* "$ROOTFS_DIR/lib/firmware/mediatek/" || true
fi
if [ -f "$KERNEL_BUILD_DIR/extra_firmware/WIFI_RAM_CODE_MT7668.bin" ]; then
  cp -v "$KERNEL_BUILD_DIR/extra_firmware/WIFI_RAM_CODE_MT7668.bin" "$ROOTFS_DIR/lib/firmware/mediatek/" || true
fi

# Copiar scripts de montagem nativa do HD interno PS4 (/dev/sda)
echo "=== Copiando scripts de montagem nativa do HD interno ==="
mkdir -p "$ROOTFS_DIR/usr/local/bin"
if [ -f "$SCRIPT_DIR/monta_particao.sh" ]; then
  cp -v "$SCRIPT_DIR/monta_particao.sh" "$ROOTFS_DIR/usr/local/bin/monta_particao.sh"
  cp -v "$SCRIPT_DIR/desmonta_particao.sh" "$ROOTFS_DIR/usr/local/bin/desmonta_particao.sh"
  cp -v "$SCRIPT_DIR/automount.sh" "$ROOTFS_DIR/usr/local/bin/automount.sh"
  chmod +x "$ROOTFS_DIR/usr/local/bin/monta_particao.sh" "$ROOTFS_DIR/usr/local/bin/desmonta_particao.sh" "$ROOTFS_DIR/usr/local/bin/automount.sh"
fi
if [ -f "$SCRIPT_DIR/../outros/tools/ps4_hdd_tools/pkg_pfs_tool/build/pkg_pfs_tool" ]; then
  cp -v "$SCRIPT_DIR/../outros/tools/ps4_hdd_tools/pkg_pfs_tool/build/pkg_pfs_tool" "$ROOTFS_DIR/usr/local/bin/pkg_pfs_tool"
  cp -v "$SCRIPT_DIR/../outros/tools/ps4_hdd_tools/pkg_pfs_tool/config.ini" "$ROOTFS_DIR/usr/local/bin/config.ini"
  chmod +x "$ROOTFS_DIR/usr/local/bin/pkg_pfs_tool"
else
  echo "AVISO: pkg_pfs_tool não encontrado em outros/tools/ps4_hdd_tools/pkg_pfs_tool/build/"
  echo "       (o PFS do HD interno não será acessível via FUSE nesta imagem)."
fi
if [ -f "$SCRIPT_DIR/../outros/tools/ps4_hdd_tools/pkg_pfs_tool/build/ps4_pfs_fuse" ]; then
  cp -v "$SCRIPT_DIR/../outros/tools/ps4_hdd_tools/pkg_pfs_tool/build/ps4_pfs_fuse" "$ROOTFS_DIR/usr/local/bin/ps4_pfs_fuse"
  chmod +x "$ROOTFS_DIR/usr/local/bin/ps4_pfs_fuse"
else
  echo "AVISO: ps4_pfs_fuse não encontrado — montagem FUSE do PFS indisponível nesta imagem."
fi

# Configurar permissões full NOPASSWD e diretórios de montagem para usuário ps4
echo "=== Configurando permissões do usuário ps4 para o HD interno ==="
mkdir -p "$ROOTFS_DIR/mnt/ps4_internal"
chmod 777 "$ROOTFS_DIR/mnt/ps4_internal"
mkdir -p "$ROOTFS_DIR/etc/sudoers.d"
echo "ps4 ALL=(ALL:ALL) NOPASSWD: ALL" > "$ROOTFS_DIR/etc/sudoers.d/ps4-hdd"
chmod 440 "$ROOTFS_DIR/etc/sudoers.d/ps4-hdd"

# Regra udev para acesso direto aos dispositivos sda, mapper e dm-* sem sudo
mkdir -p "$ROOTFS_DIR/etc/udev/rules.d"
cat > "$ROOTFS_DIR/etc/udev/rules.d/99-ps4-disk-permissions.rules" << 'UDEVEOF'
KERNEL=="sda*", GROUP="disk", MODE="0666"
KERNEL=="dm-*", GROUP="disk", MODE="0666"
ENV{DM_NAME}=="ps4_*", GROUP="disk", MODE="0666"
UDEVEOF

cat > "$ROOTFS_DIR/etc/udev/rules.d/99-ps4-media.rules" << 'UDEVEOF'
ENV{DM_NAME}=="ps4_sda27", ENV{ID_FS_LABEL}="PS4_HDD_Games", ENV{ID_FS_TYPE}="pfs", ENV{UDISKS_CAN_MOUNT}="1", ENV{UDISKS_SYSTEM}="0", ENV{UDISKS_NAME}="PS4 Internal HDD (Games)"
ENV{DM_NAME}=="ps4_sda13", ENV{ID_FS_LABEL}="PS4_HDD_System", ENV{ID_FS_TYPE}="ufs2", ENV{UDISKS_CAN_MOUNT}="1", ENV{UDISKS_SYSTEM}="0", ENV{UDISKS_NAME}="PS4 Internal HDD (System)"
UDEVEOF

# Serviço systemd de montagem automática no boot
cat > "$ROOTFS_DIR/etc/systemd/system/ps4-automount.service" << 'SERVICEEOF'
[Unit]
Description=PS4 Internal HDD Automatic Partition Mapper and FUSE Mount
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/automount.sh
ExecStop=/usr/local/bin/desmonta_particao.sh /dev/sda27

[Install]
WantedBy=multi-user.target
SERVICEEOF

ln -sf /etc/systemd/system/ps4-automount.service "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/ps4-automount.service"

# Hook custom para time= do payload
mkdir -p "$ROOTFS_DIR/etc/initcpio/install"
cat > "$ROOTFS_DIR/etc/initcpio/install/set-time-from-cmdline" << 'HOOKEOF'
#!/bin/bash
build() {
  add_runscript
}
HOOKEOF

cat > "$ROOTFS_DIR/etc/initcpio/hooks/set-time-from-cmdline" << 'HOOKEOF'
#!/bin/bash
run_hook() {
  for param in $(cat /proc/cmdline); do
    case "${param}" in
      time=*)
        TIMESTAMP="${param#time=}"
        if [ -n "${TIMESTAMP}" ] && [ "${TIMESTAMP}" -gt 0 ] 2>/dev/null; then
          date -s "@${TIMESTAMP}" || true
          hwclock -w -u || true
        fi
        ;;
    esac
  done
}
HOOKEOF

chmod +x "$ROOTFS_DIR/etc/initcpio/hooks/set-time-from-cmdline"

# Adicionar hook no mkinitcpio.conf
sed -i 's/HOOKS=(base /HOOKS=(base set-time-from-cmdline /' "$ROOTFS_DIR/etc/mkinitcpio.conf"

# Gerar initramfs
cp "$BZIMAGE" "$ROOTFS_DIR/boot/vmlinuz-$KVER_FULL"
arch-chroot "$ROOTFS_DIR" mkinitcpio -k "$KVER_FULL" -g "/boot/initramfs-$KVER_FULL.img"

echo "=== Usando initramfs recem-gerado (mkinitcpio, reflete o rootfs desta build) ==="
cp "$ROOTFS_DIR/boot/initramfs-$KVER_FULL.img" "$INITRAMFS_OUT"
# O mkinitcpio cria a imagem com umask 077 (modo 600). Os outros artefatos da
# tag ficam 644 — deixar o initramfs 600 quebra promote-release.sh e qualquer
# conferência manual feita por usuário normal (sem sudo).
chmod 644 "$INITRAMFS_OUT"

echo "=== Criando bootargs-7.0-$TAG.txt ==="
# UART (earlycon+console=uart8250,mmio32,0xC890E000 + console=tty0) e rootwait
# (nao rootdelay) sao obrigatorios aqui -- ver AGENTS.md secao "Convencoes de
# bootargs (validadas ao vivo)". Sem UART o log de boot fica cego; rootdelay=N
# dorme os N segundos completos mesmo com o disco pronto (rootwait mede ~10.5s
# mais rapido, validado 2026-07-28). Incidente 2026-07-30: este heredoc ainda
# tinha console=tty0 sem UART e rootdelay=10 -- 02-burn-image-7.0.sh grava
# esse bootargs.txt direto, sem passar pela tag validada em boot_referencia/.
cat > "$BOOTARGS_OUT" << 'CMDLINEEOF'
panic=0 clocksource=tsc consoleblank=0 net.ifnames=0 radeon.dpm=0 amdgpu.dpm=0 drm.debug=0x06 earlycon=uart8250,mmio32,0xC890E000 console=uart8250,mmio32,0xC890E000 console=tty0 keep_bootcon earlyprintk=efi,keep loglevel=8 root=LABEL=psxitarch rw rootwait systemd.unified_cgroup_hierarchy=0 systemd.legacy_systemd_cgroup_controller=yes audit=0 amdgpu.audio=1 usbcore.autosuspend=-1 video=HDMI-A-1:1920x1080@60 mitigations=off zswap.enabled=1 log_buf_len=4M libata.force=1.00:3.0Gbps,noncq ahci.mobile_lpm_policy=1 netconsole=@192.168.0.2/eth0,6666@192.168.0.1/ff:ff:ff:ff:ff:ff
CMDLINEEOF

echo "=== Gerando /etc/fstab (raiz + share CIFS do adsv2) ==="
# O build nunca gerava /etc/fstab (a raiz monta por root=LABEL no cmdline). As duas
# entradas abaixo tiram a configuracao da maquina viva:
#  - raiz: noatime (menos escrita no SSD via bridge USB) e errors=remount-ro (o SSD
#    do PS4 esta falhando; ver BACKLOG, P0);
#  - CIFS: share [dados_aux] do adsv2 com uid/gid 1001 (usuario local anderson).
#    nofail + x-systemd.automount: sem rede o boot nao trava, monta no 1o acesso.
#    Ver outros/docs/BACKLOG.md, item "Habilitar o cliente CIFS/SMB".
cat > "$ROOTFS_DIR/etc/fstab" << 'FSTABEOF'
LABEL=psxitarch  /               ext4  rw,noatime,errors=remount-ro  0 1
//192.168.6.101/dados_aux  /mnt/hdauxiliar  cifs  guest,uid=1001,gid=1001,forceuid,forcegid,vers=3.0,iocharset=utf8,file_mode=0644,dir_mode=0755,_netdev,nofail,x-systemd.automount,x-systemd.mount-timeout=10s  0 0
FSTABEOF
mkdir -p "$ROOTFS_DIR/mnt/hdauxiliar"

echo "=== Copiando vram.txt ==="
if [ ! -f "$BOOT_DIR/vram.txt" ]; then
  echo "1024" > "$BOOT_DIR/vram.txt"
fi

echo "=== Criando tarball do rootfs ==="
tar -C "$ROOTFS_DIR" -cf "$OUTPUT_TAR" .

echo "=== Resumo ==="
echo "TAG: $TAG"
echo "Kernel version: $KVER_FULL"
echo "Rootfs tarball: $OUTPUT_TAR"
echo "Initramfs: $INITRAMFS_OUT"
echo "Bootargs: $BOOTARGS_OUT"
echo "Config: $CONFIG"
echo "bzImage: $BZIMAGE"
if [ -f "$MESA_PATCHED_TAR" ]; then
  echo "Mesa patchado (Gladius/Liverpool): INCLUIDO em /opt/mesa-ps4-patched + /etc/environment"
else
  echo "Mesa patchado (Gladius/Liverpool): NAO incluido (rode mesa/01-build-mesa.sh antes)"
fi
echo ""
echo "Próximos passos:"
echo "  sudo ./02-burn-image-7.0.sh /dev/sdX $TAG    (grava tudo, refaz o HD)"
echo "  sudo ./deploy-boot-7.0.sh $TAG               (só o boot, mantém o rootfs)"

# Sentinela de conclusão — evita ambiguidade sobre status do build
COMPLETE_MARKER="$BOOT_DIR/.build-complete-$TAG"
touch "$COMPLETE_MARKER"
echo "=== BUILD COMPLETO: $TAG ==="
echo "Sentinela criada: $COMPLETE_MARKER"
