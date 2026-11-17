#!/bin/bash
# install-modules-7.0.sh — instala módulos do kernel 7.0 no rootfs
# Remove BTF de todos os módulos para evitar mismatch ao carregar no PS4
# Uso: sudo ./install-modules-7.0.sh <ROOTFS_DIR> <KERNEL_BUILD_DIR> <KVER_FULL>

set -euo pipefail

ROOTFS_DIR="${1:-}"
KERNEL_BUILD_DIR="${2:-}"
KVER_FULL="${3:-}"

if [ -z "$ROOTFS_DIR" ] || [ -z "$KERNEL_BUILD_DIR" ] || [ -z "$KVER_FULL" ]; then
    echo "Uso: $0 <ROOTFS_DIR> <KERNEL_BUILD_DIR> <KVER_FULL>"
    exit 1
fi

MODULES_DIR="$ROOTFS_DIR/lib/modules/$KVER_FULL"

echo "=== install-modules-7.0.sh: instalando módulos para $KVER_FULL ==="

# 1. modules_install oficial (com strip de debug symbols)
echo "--- modules_install (INSTALL_MOD_STRIP=1) ---"
make -C "$KERNEL_BUILD_DIR" \
    INSTALL_MOD_PATH="$ROOTFS_DIR" \
    INSTALL_MOD_STRIP=1 \
    modules_install

# 2. Remover BTF de TODOS os módulos instalados
# BTF é para BPF CO-RE (bpftrace/BCC/libbpf) — não usado no PS4
# O mismatch de BTF impede carregar módulos compilados em build anterior
echo "--- Removendo BTF de todos os módulos (.ko) ---"
find "$MODULES_DIR" -name '*.ko' -type f | while read -r ko; do
    if objdump -h "$ko" 2>/dev/null | grep -q '\.BTF'; then
        echo "  Stripping BTF: $ko"
        objcopy --remove-section=.BTF --remove-section=.BTF.base "$ko" "$ko.strip" && mv "$ko.strip" "$ko"
    fi
done

# 3. Garantir módulos PS4-specific (alguns podem não ser instalados pelo modules_install padrão)
#    se não estiverem no modules.builtin ou modules.order
echo "--- Verificando módulos PS4-specific ---"

# Lista de módulos que devem existir (compilados como =m no kernel build)
PS4_MODULES=(
    "drivers/net/ethernet/sony/mts.ko"
    "fs/smb/client/cifs.ko"
    "fs/netfs/netfs.ko"
    "fs/smb/common/cifs_md4.ko"
    "fs/smb/client/smb2_mapping_table.ko"
    "drivers/dma/baikal-dmac.ko"
    "drivers/dma/virt-dma.ko"
    "drivers/dma/dmatest.ko"
    "drivers/watchdog/baikal_wdt.ko"
    "drivers/clocksource/baikal-hpet.ko"
    "drivers/rtc/rtc-ps4-icc.ko"
    "drivers/misc/baikal-memory.ko"
    "drivers/block/baikal-spm-blk.ko"
)

for mod_rel in "${PS4_MODULES[@]}"; do
    src="$KERNEL_BUILD_DIR/$mod_rel"
    dst="$MODULES_DIR/kernel/$mod_rel"
    if [ -f "$src" ]; then
        mkdir -p "$(dirname "$dst")"
        cp -v "$src" "$dst"
        # Strip BTF da cópia também
        if objdump -h "$dst" 2>/dev/null | grep -q '\.BTF'; then
            objcopy --remove-section=.BTF --remove-section=.BTF.base "$dst" "$dst.strip" && mv "$dst.strip" "$dst"
        fi
    else
        echo "AVISO: módulo PS4 não encontrado no kernel build: $mod_rel"
    fi
done

# 4. Sobrescrever mts.ko com o de drivers_mts/build/ se existir (mais recente)
MTS_LOCAL_KO="$KERNEL_BUILD_DIR/../drivers_mts/build/mts.ko"
if [ -f "$MTS_LOCAL_KO" ]; then
    dst="$MODULES_DIR/kernel/drivers/net/ethernet/sony/mts.ko"
    echo "--- Sobrescrevendo mts.ko com drivers_mts/build/mts.ko ---"
    mkdir -p "$(dirname "$dst")"
    cp -v "$MTS_LOCAL_KO" "$dst"
    if objdump -h "$dst" 2>/dev/null | grep -q '\.BTF'; then
        objcopy --remove-section=.BTF --remove-section=.BTF.base "$dst" "$dst.strip" && mv "$dst.strip" "$dst"
    fi
fi

# 5. depmod
echo "--- depmod -a ---"
arch-chroot "$ROOTFS_DIR" depmod -a "$KVER_FULL"

# 6. Resumo
echo "=== Módulos instalados em $MODULES_DIR ==="
find "$MODULES_DIR" -name '*.ko' -type f | wc -l | xargs echo "Total .ko:"
echo "Módulos PS4-specific:"
for mod_rel in "${PS4_MODULES[@]}"; do
    dst="$MODULES_DIR/kernel/$mod_rel"
    if [ -f "$dst" ]; then
        btf_status="OK"
        objdump -h "$dst" 2>/dev/null | grep -q '\.BTF' && btf_status="BTF PRESENTE (PROBLEMA!)"
        echo "  $mod_rel — $btf_status"
    else
        echo "  $mod_rel — FALTANDO"
    fi
done

echo "=== install-modules-7.0.sh concluído ==="