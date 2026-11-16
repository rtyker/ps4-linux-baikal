#!/bin/bash
# monitor_build_and_deploy.sh — Monitora a compilação do kernel, faz o deploy no /dev/sda1 e notifica via ntfy
set -euo pipefail

# Frente 1 (kernel/): monitora o build e chama o deploy da frente 2 (distro/).
KERNEL_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
DISTRO_DIR="$(cd "$KERNEL_DIR/../distro" && pwd)"
BOOT_REF="${PS4_BOOT_REF:-$KERNEL_DIR/../distro/boot_referencia}"
NOTIFICA_SCRIPT="/home/anderson/scripts/notifica-projeto/notifica.sh"

echo "=== Monitor de Build & Deploy iniciado ==="

# Aguarda até que os processos de compilação (clang, make, ld.lld) terminem no sistema
while pgrep -f "clang|ld.lld|make" >/dev/null 2>&1; do
  sleep 5
done

echo "=== Compilação finalizada ==="
sleep 3

# Encontra a imagem mais recente gerada na pasta boot_referencia
LATEST_BZIMAGE=$(ls -t "$BOOT_REF"/bzImage-7.0-* 2>/dev/null | head -n 1 || echo "")

if [ -z "$LATEST_BZIMAGE" ]; then
  "$NOTIFICA_SCRIPT" -p urgente -t "PS4 Linux ERRO" "Compilação do kernel falhou ou bzImage não foi encontrado!"
  exit 1
fi

TAG=$(basename "$LATEST_BZIMAGE" | sed 's/bzImage-7.0-//')
echo "=== Tag identificada: $TAG ==="

# Sem fallback silencioso: cada tag precisa do seu initramfs e bootargs. Se faltar
# algum, avisa e para — copiar de uma tag antiga trocaria duas variáveis de uma vez
# sem ninguém perceber (ver AGENTS.md / deploy-boot-7.0.sh).
MISSING=0
[ -f "$BOOT_REF/initramfs-7.0-$TAG.cpio.gz" ] || { echo "ERRO: initramfs-7.0-$TAG.cpio.gz ausente em $BOOT_REF"; MISSING=1; }
[ -f "$BOOT_REF/bootargs-7.0-$TAG.txt" ]     || { echo "ERRO: bootargs-7.0-$TAG.txt ausente em $BOOT_REF"; MISSING=1; }
if [ "$MISSING" -ne 0 ]; then
  "$NOTIFICA_SCRIPT" -p urgente -t "PS4 Linux ERRO" "Tag $TAG incompleta (falta initramfs ou bootargs) — deploy abortado."
  exit 1
fi

# Realiza o deploy automático no HD (frente 2) com sudo
sudo "$DISTRO_DIR/deploy-boot-7.0.sh" "$TAG"

# Envia a notificação para o celular
"$NOTIFICA_SCRIPT" -p high -t "PS4 Linux Sucesso" "Build e Deploy da tag '$TAG' no HD (/dev/sda1) concluídos com SUCESSO! Pronto para dar boot no PS4."

echo "=== Processo completo e notificação enviada ==="
