#!/bin/bash
# aeolia_dmac_prep.sh — Preparar PS4 para teste do Aeolia DMAC
# ATENÇÃO: Descarrega drivers xhci_aeolia e ahci — PERDE USB E SATA!
# Use apenas para teste controlado do harness aeolia_dmac_test.
# Restaurar com reboot ou recarregando os módulos.

set -euo pipefail

PS4_IP="${PS4_IP:-192.168.6.128}"
PS4_PASS="${PS4_PASS:-ps4}"

ssh_cmd() {
    sshpass -p "$PS4_PASS" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$PS4_IP" "$@"
}

scp_cmd() {
    sshpass -p "$PS4_PASS" scp -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$@"
}

echo "=== Preparando PS4 para teste Aeolia DMAC ==="
echo "PS4: $PS4_IP"
echo ""

# 1. Verificar estado atual
echo "1. Verificando drivers carregados..."
ssh_cmd "lsmod | grep -E 'xhci_aeolia|ahci|aeolia' || echo '  Nenhum driver Aeolia/AHCI carregado'"

# 2. Descarregar drivers que usam 00:14.7
echo ""
echo "2. Descarregando drivers do Aeolia (00:14.7)..."
echo "   ATENÇÃO: Isso vai derrubar USB e SATA interno!"

ssh_cmd "rmmod xhci_aeolia 2>/dev/null && echo '  xhci_aeolia descarregado' || echo '  xhci_aeolia não estava carregado'"
ssh_cmd "rmmod ahci 2>/dev/null && echo '  ahci descarregado' || echo '  ahci não estava carregado'"
ssh_cmd "rmmod xhci_pci 2>/dev/null && echo '  xhci_pci descarregado' || echo '  xhci_pci não estava carregado'"

# 3. Verificar se device 00:14.7 está livre
echo ""
echo "3. Verificando device 00:14.7..."
ssh_cmd "lspci -nn -d 104d:90ce -d 104d:90a3 2>/dev/null || lspci -nn | grep '00:14.7' || echo '  Device 00:14.7 não listado (pode estar sem driver)'"

# 4. Compilar e copiar harness (se fornecido)
if [ -n "${1:-}" ]; then
    KO_FILE="$1"
    if [ -f "$KO_FILE" ]; then
        echo ""
        echo "4. Copiando harness $KO_FILE..."
        scp_cmd "$KO_FILE" "root@$PS4_IP:/tmp/aeolia_dmac_test.ko"
        echo "   Copiado para /tmp/aeolia_dmac_test.ko"
    else
        echo "ERRO: Arquivo $KO_FILE não encontrado"
        exit 1
    fi
else
    echo ""
    echo "4. Harness não especificado — pule a cópia"
    echo "   Uso: $0 /caminho/para/aeolia_dmac_test.ko"
fi

# 5. Carregar harness
echo ""
echo "5. Para carregar o harness:"
echo "   ssh root@$PS4_IP 'insmod /tmp/aeolia_dmac_test.ko run=1 bar=0 tests=1 src_spm=1 spm_offset=0 bigkb=256'"
echo ""
echo "   Parâmetros principais:"
echo "     run=1           - executa testes"
echo "     bar=0|2         - qual BAR do Aeolia (testar ambos)"
echo "     tests=1|4|8     - 1=simples(256B) 4=grande 8=alinhamentos"
echo "     src_spm=1       - DMAC lê da SPM (0x80000000+offset)"
echo "     dst_spm=1       - DMAC escreve na SPM"
echo "     spm_base=0x80000000  - endereço base candidato (H1)"
echo "     spm_offset=0    - offset na janela SPM (< 4 MiB)"
echo "     bigkb=256       - tamanho do teste grande em KiB"
echo "     irqmode=1       - usa IRQ real (MSI) em vez de polling"
echo ""

echo "=== Preparação concluída ==="
echo ""
echo "PRÓXIMOS PASSOS NO PS4:"
echo "  1. Carregar harness com parâmetros desejados"
echo "  2. Verificar dmesg: dmesg -T | grep -i aeolia"
echo "  3. Se PASS: testar others offsets/tamanhos"
echo "  4. Se FAIL: tentar spm_base=0xC0000000 (H2) ou others candidatos"
echo "  5. Restaurar drivers: modprobe xhci_aeolia ahci (ou reboot)"