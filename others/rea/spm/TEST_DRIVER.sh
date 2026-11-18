#!/bin/bash
# =============================================================================
# Script de Teste - Driver Baikal Memory (SPM/DDR3, 00:14.6)
# =============================================================================
# Uso: ./TEST_DRIVER.sh [usuario] [senha] [ip]
# Padrão: usuario_dev / usuario_dev / 192.168.6.128
# =============================================================================

USER="${1:-usuario_dev}"
PASS="${2:-usuario_dev}"
IP="${3:-192.168.6.128}"
REMOTE_PATH="/mnt/hdauxiliar/ps4-linux-baikal/others/rea/spm/dumps/baikal-memory.ko"

set -e

echo "================================================================"
echo "  Teste do Driver Baikal Memory (SPM/DDR3, 00:14.6)"
echo "================================================================"
echo "Alvo: $USER@$IP"
echo "Modulo: $REMOTE_PATH"
echo ""

# Verificar se o arquivo .ko existe localmente
if [ ! -f "/mnt/hdauxiliar/ps4-linux-baikal/others/rea/spm/dumps/baikal-memory.ko" ]; then
    echo "ERRO: Arquivo baikal-memory.ko não encontrado localmente!"
    echo "Execute primeiro o build no adsv2."
    exit 1
fi

echo "[1/6] Copiando módulo para o PS4 via CIFS..."
# O arquivo já está no share CIFS, acessível via /mnt/hdauxiliar no PS4
echo "   Arquivo ja esta disponivel via CIFS em:"
    echo "   /mnt/hdauxiliar/ps4-linux-baikal/others/rea/spm/dumps/baikal-memory.ko"

echo ""
echo "[2/6] Carregando modulo no PS4..."
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$USER@$IP" "
    sudo insmod /mnt/hdauxiliar/ps4-linux-baikal/others/rea/spm/dumps/baikal-memory.ko 2>&1
    echo '---'
    echo 'Modulo carregado. Verificando...'
    lsmod | grep baikal
    dmesg | tail -5
"

echo ""
echo "[3/6] Verificando dispositivo de caractere..."
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$USER@$IP" "
    ls -l /dev/baikal-memory 2>&1 || echo 'Erro: /dev/baikal-memory nao encontrado'
"

echo ""
echo "[4/6] Testando leitura da SPM (primeiros 256 bytes do BAR5)..."
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$USER@$IP" "
    sudo dd if=/dev/baikal-memory bs=1 count=256 2>/dev/null | xxd
"

echo ""
echo "[5/6] Testando sysfs..."
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$USER@$IP" "
    echo 'Registradores BAR5:'
    for reg in 0x00 0x04 0x08 0x0c 0x10 0x14 0x18 0x1c; do
        val=\$(cat /sys/class/baikal-memory/bar5_\$reg 2>/dev/null || echo 'N/A')
        echo "   bar5_\$reg = \$val"
    done
"

echo ""
echo "[6/6] Descarga do modulo..."
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$USER@$IP" "
    sudo rmmod baikal-memory 2>&1
    echo 'Modulo descarregado.'
    dmesg | tail -3
"

echo ""
echo "================================================================"
echo "  Teste concluído!"
echo "================================================================"
