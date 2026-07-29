#!/bin/bash
# monitor_build_and_deploy.sh — Monitora a compilação do kernel, faz o deploy no /dev/sda1 e notifica via ntfy
set -euo pipefail

SCRIPT_DIR="/mnt/t/downloads/PS4/linux_in_ps4/distros/arch_minimal_v2"
NOTIFICA_SCRIPT="/home/anderson/scripts/notifica-projeto/notifica.sh"

echo "=== Monitor de Build & Deploy iniciado ==="

# Aguarda até que os processos de compilação (clang, make, ld.lld) terminem no sistema
while pgrep -f "clang|ld.lld|make" >/dev/null 2>&1; do
  sleep 5
done

echo "=== Compilação finalizada ==="
sleep 3

# Encontra a imagem mais recente gerada na pasta boot_referencia
LATEST_BZIMAGE=$(ls -t "$SCRIPT_DIR/boot_referencia"/bzImage-7.0-* 2>/dev/null | head -n 1 || echo "")

if [ -z "$LATEST_BZIMAGE" ]; then
  "$NOTIFICA_SCRIPT" -p urgente -t "PS4 Linux ERRO" "Compilação do kernel falhou ou bzImage não foi encontrado!"
  exit 1
fi

TAG=$(basename "$LATEST_BZIMAGE" | sed 's/bzImage-7.0-//')
echo "=== Tag identificada: $TAG ==="

# Se a tag nova não tiver o initramfs com seu nome exato, reusa o de 20260720-sky2len-fix
if [ ! -f "$SCRIPT_DIR/boot_referencia/initramfs-7.0-$TAG.cpio.gz" ]; then
  cp "$SCRIPT_DIR/boot_referencia/initramfs-7.0-20260720-sky2len-fix.cpio.gz" "$SCRIPT_DIR/boot_referencia/initramfs-7.0-$TAG.cpio.gz"
fi
if [ ! -f "$SCRIPT_DIR/boot_referencia/bootargs-7.0-$TAG.txt" ]; then
  cp "$SCRIPT_DIR/boot_referencia/bootargs-7.0-20260720-sky2len-fix.txt" "$SCRIPT_DIR/boot_referencia/bootargs-7.0-$TAG.txt"
fi

# Realiza o deploy automático no HD /dev/sda1 com sudo
cd "$SCRIPT_DIR"
sudo ./deploy-boot-7.0.sh "$TAG"

# Envia a notificação para o celular
"$NOTIFICA_SCRIPT" -p high -t "PS4 Linux Sucesso" "Build e Deploy da tag '$TAG' no HD (/dev/sda1) concluídos com SUCESSO! Pronto para dar boot no PS4."

echo "=== Processo completo e notificação enviada ==="
