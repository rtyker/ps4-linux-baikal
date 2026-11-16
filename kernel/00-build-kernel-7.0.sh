#!/bin/bash
# 00-build-kernel-7.0.sh — Compila o kernel Strawberry 7.0 para PS4 Baikal
# Script ÚNICO e OFICIAL de build (ThinLTO, General profile, Baikal) — roda
# sem parâmetros. Não depende mais do build.sh do repo upstream (removido do
# fluxo em 2026-07-22, ver comentário mais abaixo perto do `rm -f build.sh`).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Toda a parafernália de build mora DENTRO do projeto, em kernel/
# (gitignored): kernel_build_7.0/, .ccache/, snapshots/
# Motivo (2026-11-11): antes o build dependia de /mnt/hdauxiliar/temp/,
# o que exigia mover/copiar estado entre diretórios a cada sessão.
# então não há mais razão para o build sair da estrutura do projeto.
KERNEL_BUILD_ROOT="$SCRIPT_DIR"
KERNEL_SRC_DIR="$KERNEL_BUILD_ROOT/kernel_build_7.0"
# KERNEL_BACKUP_DIR removido (tree_backups/ apagado 2026-11-11)
SNAPSHOT_DIR="$SCRIPT_DIR/snapshots"
# Lista de firmwares embutidos no kernel (CONFIG_EXTRA_FIRMWARE). Fonte única:
# usada tanto no scripts/config quanto no preflight (checagem de existência).
EXTRA_FIRMWARE_LIST="mrvl/sd8897_uapsta.bin mrvl/sd8797_uapsta.bin mediatek/mt7668pr2h.bin EEPROM_MT7668.bin EEPROM_MT7668_e1.bin mt7668_patch_e1_hdr.bin mt7668_patch_e2_hdr.bin TxPwrLimit_MT76x8.dat wifi.cfg WIFI_RAM_CODE2_SDIO_MT7668.bin WIFI_RAM_CODE2_USB_MT7668.bin WIFI_RAM_CODE_MT7668.bin"
# Frente 2 (distro) — usada no fallback de config versionada (RELEASE/v1.0.0)
# e nos caminhos das instruções finais. Não é validada de propósito: o build
# do kernel em si não depende dela.
DISTRO_DIR="$SCRIPT_DIR/../distro"
# ── Origem do código do kernel ─────────────────────────────────────────────
# A ÁRVORE LOCAL em $KERNEL_SRC_DIR é a FONTE DA VERDADE do código desde
# 2026-11-11. Motivo (investigado ao vivo nesta data):
#   github.com/rmuxnet/linux  → HTTP 404, repositório apagado;
#   gitlab.com/rmuxnet/linux  → vivo (projeto "PS4 Strawberry Kernel"), mas
#     publica SÓ o branch `ps4/7.3.3` (kernel 7.3.3). O nosso
#     `baikal/7.0.8-Stable` não é mais publicado lá, embora o commit base
#     d8cbb8e91 continue existindo no histórico do GitLab.
# Além disso nós divergimos do upstream de propósito (patches em patches/ e
# drivers_mts/), então build reprodutível = esta árvore + os patches, sem
# depender de rede. As URLs abaixo ficam apenas como REGISTRO HISTÓRICO de
# onde o código veio; NÃO são usadas para obter código. Se a árvore sumir,
# restaure do snapshot (ver kernel/README.md).
UPSTREAM_URL_HISTORICO="https://gitlab.com/rmuxnet/linux.git"  # vivo, sem o nosso branch
UPSTREAM_URL_ANTIGO="https://github.com/rmuxnet/linux.git"     # 404 desde 2026-11
BRANCH="baikal/7.0.8-Stable"

# TAG identifica esta variante de build (ex: "sky2builtin", "baseline").
# Cada build fica com nome próprio em boot_referencia/ para permitir comparar
# vários kernels testados. A renomeação para o nome genérico (bzImage,
# bootargs.txt) só acontece no HD de destino, via deploy-boot-7.0.sh.
# Roda sem parâmetro nenhum (TAG usa o default abaixo) — script único e
# oficial de build, sem depender de nenhum build.sh externo (ver 2026-07-22:
# o build.sh do upstream rmuxnet/linux foi incorporado aqui e removido do
# fluxo, pra ter só um script pra manter/entender).
TAG="${1:-$(date +%Y%m%d)-sky2builtin}"
# Artefatos de boot pertencem à FRENTE 2 (distro/): pasta única, consumida por
# deploy-boot/01-build-image/02-burn-image/promote-release. Decisão de 2026-11-11
# (antes vivia em kernel/boot_referencia/).
BOOT_DIR="$DISTRO_DIR/boot_referencia"
OUTPUT_BZIMAGE="$BOOT_DIR/bzImage-7.0-$TAG"
OUTPUT_CONFIG="$BOOT_DIR/config-7.0-$TAG"
# boot_referencia/ é build output (gitignored) e pode não existir num clone novo.
# Sem isso o cp do bzImage falha no primeiro build de uma máquina limpa.
mkdir -p "$BOOT_DIR"

# Flags de compilação PS4 Jaguar (idênticas às que o build.sh upstream usava)
export KCFLAGS="-march=btver2 -mtune=btver2 -Os"
export KAFLAGS="-march=btver2 -mtune=btver2 -Os"
export HOSTCFLAGS="-Wno-error=incompatible-pointer-types-discards-qualifiers"
# JOBS=2 limita o paralelismo do pahole na geração do BTF. Em
# scripts/Makefile.btf o kbuild faz `JOBS := $(patsubst -j%,%,$(MAKEFLAGS))`,
# ou seja o pahole herda o -j do build inteiro (-j8) — e foi assim que ele
# chegou a 9,4 GB de RSS e causou o OOM de 2026-07-22. Como `JOBS :=` é
# atribuição simples no makefile, uma atribuição na linha de comando tem
# precedência. Isso mantém o build rápido e o pahole contido, sem precisar
# desabilitar o BTF (o que quebrou o boot — ver comentário na seção DEBUG_INFO).
export CCACHE_DIR="${PS4_CCACHE_DIR:-$KERNEL_BUILD_ROOT/.ccache}"
MAKE_OPTS=(-j"$(nproc)" JOBS=2 LLVM=1 CC="ccache clang" ARCH=x86_64 HOSTCFLAGS="${HOSTCFLAGS}")

echo "=== Build tag: $TAG ==="

# Robust cleanup - unmount any stray mounts before removing dirs
cleanup_build_dir() {
  set +e
  if [ -d "$KERNEL_SRC_DIR" ]; then
    findmnt -R "$KERNEL_SRC_DIR" -n -o TARGET 2>/dev/null | sort -r | while read -r mp; do
      mountpoint -q "$mp" && umount -l "$mp" 2>/dev/null || true
    done
  fi
  sleep 0.5
  set -e
}
trap cleanup_build_dir EXIT INT TERM

# 🔴 REGRA CRÍTICA (AGENTS.md "Idempotência de Alterações no Kernel"):
# git reset --hard / git clean -fdx descartam qualquer mudança não commitada em
# arquivos rastreados. Isso já causou perda real de trabalho (SATA polling de
# 2026-07-30, nunca extraído para patches/, perdido no build de 2026-08-01).
#
# Antes de resetar, esta função SALVA o estado (diff + untracked) num diretório
# com timestamp e imprime o caminho — nada é apagado em silêncio. Ela não aborta
# mais: agora que a árvore local é a fonte da verdade, os patches aplicados de
# rodadas anteriores deixam drivers/ata/etc "sujos" de propósito (git apply sem
# commit, por design) — abortar tornaria o build impossível a partir do segundo
# run. O que a regra exige é "extrair ANTES da perda", não "abortar".
save_dirty_state() {
  local ts dir
  ts="$(date +%Y%m%d-%H%M%S)"
  dir="/tmp/kernel-pre-reset-$ts"
  mkdir -p "$dir"
  git diff HEAD > "$dir/HEAD.patch" || true
  git status --porcelain > "$dir/git-status.txt" || true
  git ls-files --others --exclude-standard -z \
    | tar -czf "$dir/untracked.tar.gz" --null -T - 2>/dev/null || true
  echo "  ⚠ estado não commitado salvo em: $dir"
  echo "    (HEAD.patch, git-status.txt, untracked.tar.gz)"
}

# ── Preflight ──────────────────────────────────────────────────────────────
# Falha CEDO, antes de qualquer reset/clean, se o ambiente não estiver pronto:
# ferramentas, espaço em disco, patches, config e os firmwares embutidos. Um
# erro no meio do build custa 20-45 min e pode deixar a árvore em estado
# parcial; a checagem de firmware evita o erro críptico do kbuild no meio do
# `make`. Todas as verificações são somente-leitura (nada é alterado aqui).
die() { echo "❌ ERRO FATAL: $*" >&2; exit 1; }

preflight() {
  local missing=() c avail_kb p fw fw_missing=""
  for c in git make clang ld.lld llvm-ar ccache zstd curl tar findmnt \
           mountpoint nproc stat awk sed grep pahole flex bison bc perl; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    die "ferramentas ausentes no PATH: ${missing[*]}"
  fi

  mkdir -p "$KERNEL_BUILD_ROOT" "$SNAPSHOT_DIR" "$BOOT_DIR" \
    || die "não foi possível criar os diretórios de build"
  [ -w "$KERNEL_BUILD_ROOT" ] || die "sem permissão de escrita em $KERNEL_BUILD_ROOT (rode com sudo)"
  [ -w "$SNAPSHOT_DIR" ]      || die "sem permissão de escrita em $SNAPSHOT_DIR (rode com sudo)"

  if [ "$(id -u)" -ne 0 ]; then
    echo "❌ ERRO FATAL: este script DEVE ser executado com sudo (root)." >&2
    echo "   Rode: sudo ./00-build-kernel-7.0.sh $TAG" >&2
    exit 1
  fi

  avail_kb=$(df -Pk "$SCRIPT_DIR" | awk 'NR==2{print $4}')
  if [ "${avail_kb:-0}" -lt $((10 * 1024 * 1024)) ]; then
    die "espaço livre insuficiente em $SCRIPT_DIR: ${avail_kb} KB (mínimo 10 GiB)"
  fi

  # Patches que o build aplica (os 'git apply --check' reais rodam pós-reset).
  for p in ahci-baikal-polling-fallback.patch ps4-icc-rtc-wrapper.patch \
           ps4-icc-proc-debug.patch mts-baikal-gbe-driver.patch \
           baikal-memory-fase2.patch baikal-dmac.patch \
           clocksource-baikal-hpet.patch baikal-wdt.patch \
           ps4-bridge-dp-init.patch ps4-bridge-link-rate.patch \
           ps4-bridge-keep-mode.patch; do
    [ -f "$SCRIPT_DIR/patches/$p" ] || die "patch ausente: $SCRIPT_DIR/patches/$p"
  done

  # Config base: o 'config' rastreado na árvore é a garantia final (o reset
  # restaura; os candidatos em distro/boot_referencia/ e distro/RELEASE são extras).
  git cat-file -e "HEAD:config" 2>/dev/null \
    || die "árvore sem 'config' rastreado — estado inconsistente, restaure do snapshot"

  # Firmwares embutidos: todos precisam existir. O git clean preserva
  # extra_firmware/ (-e), então checar antes do reset é válido.
  for fw in $EXTRA_FIRMWARE_LIST; do
    [ -s "$KERNEL_SRC_DIR/extra_firmware/$fw" ] || fw_missing="$fw_missing $fw"
  done
  [ -z "$fw_missing" ] || die "firmwares ausentes em extra_firmware/:$fw_missing"

  echo "✓ Preflight OK (dependências, espaço, patches, config e firmwares)"
}

echo "=== Configurando diretório de build ==="
cleanup_build_dir

if [ ! -d "$KERNEL_SRC_DIR/.git" ]; then
  echo "❌ ERRO: árvore do kernel ausente em $KERNEL_SRC_DIR"
  echo ""
  echo "A árvore local é a fonte da verdade do código: o upstream não publica"
  echo "mais o branch $BRANCH (ver comentário no topo deste script)."
  echo "Restaure do snapshot mais recente:"
  echo "  ls -1t $SNAPSHOT_DIR/kernel-src-*.tar.zst | head -1"
  echo "  sudo tar -I zstd -xf <snapshot> -C $KERNEL_BUILD_ROOT"
  echo "Ver kernel/README.md, seção 'Restaurar a árvore a partir de um snapshot'."
  exit 1
fi

cd "$KERNEL_SRC_DIR"

CURRENT_BRANCH="$(git branch --show-current 2>/dev/null || echo "")"
if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
  echo "Branch local '$CURRENT_BRANCH' != '$BRANCH' — trocando para $BRANCH (local)."
  git rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null \
    || die "branch local '$BRANCH' não existe — restaure a árvore do snapshot (ver README)"
  git checkout "$BRANCH"
fi

preflight

echo "Fonte: árvore local $KERNEL_SRC_DIR @ $(git rev-parse --short HEAD) (branch $BRANCH)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "Mudanças não commitadas na árvore (patches de rodada anterior) — salvando antes do reset."
  save_dirty_state
fi

echo "Resetando para o HEAD local e limpando artefatos (árvore prístina)..."
git reset --hard HEAD
# -e .config        : config do baseline (não rastreado pelo git)
# -e extra_firmware : firmwares embutidos (sd8897/sd8797/mt7668). O
#   sd8797_uapsta.bin (Orbis/WiFi) NÃO existe em nenhum outro lugar — um
#   'git clean -fdx' sem este -e apagaria a única cópia que temos (verificado
#   2026-11-11; backup em kernel/kernels/backup_kernel_tree_20261111/ — pasta removida).
git clean -fdx -e .config -e extra_firmware

# RTC via ICC (drivers/rtc/rtc-ps4-icc.c + Kconfig/Makefile + wrapper
# ps4_icc_rtc_cmd() em drivers/ps4/) é aplicado inteiramente pelo patch
# patches/ps4-icc-rtc-wrapper.patch mais abaixo (fonte única — um heredoc
# criava rtc-ps4-icc.c aqui e um sed injetava Kconfig/Makefile em paralelo
# ao patch, o que fazia o patch falhar por conflito de contexto todo build,
# silenciosamente engolido pelo "|| echo AVISO"; ver
# memory/regressao-sata-2026-08-01-diagnostico-e-solucao.md). NÃO recriar
# esses arquivos aqui — deixar só para o patch.

# Aplicar patch de SATA polling (fallback para PxIE=0 no Baikal)
# Este patch é ESSENCIAL para operação estável do ata1 (HD interno do PS4) —
# ver memory/regressao-sata-2026-08-01-diagnostico-e-solucao.md. Usa `git apply`
# (não `patch -p1`) porque é não-interativo, falha com exit code claro em vez
# de gerar .rej silenciosos, e valida a árvore inteira antes de tocar em
# qualquer arquivo (--check).
echo "=== Aplicando patch de AHCI polling fallback (SATA Baikal) ==="
AHCI_PATCH="$SCRIPT_DIR/patches/ahci-baikal-polling-fallback.patch"
if [ ! -f "$AHCI_PATCH" ]; then
  echo "❌ ERRO FATAL: $AHCI_PATCH não encontrado"
  echo "  SATA interno (ata1) sofrerá timeout/disable device sem este patch."
  exit 1
fi

if ! git apply --check "$AHCI_PATCH" 2>/tmp/ahci_patch_check.log; then
  echo "❌ ERRO FATAL: patch AHCI polling não aplica contra o kernel atual:"
  cat /tmp/ahci_patch_check.log
  echo ""
  echo "  Isso normalmente significa que o upstream do kernel mudou drivers/ata/."
  echo "  Regenere o patch: edite ahci.h/ahci.c/libahci.c, valide com"
  echo "  'make drivers/ata/{ahci,libahci}.o', depois 'git diff HEAD -- drivers/ata/'"
  echo "  e substitua $AHCI_PATCH."
  exit 1
fi

git apply "$AHCI_PATCH"
echo "✓ Patch AHCI polling aplicado com sucesso (git apply, validado com --check)"

echo "=== Preparando firmware extra ==="
mkdir -p extra_firmware/{mrvl,mediatek,amdgpu}

# Firmware Marvell (Aeolia/Belize WiFi) - necessário mesmo no Baikal (CONFIG_EXTRA_FIRMWARE)
if [ ! -f "extra_firmware/mrvl/sd8897_uapsta.bin" ]; then
  echo "Baixando sd8897_uapsta.bin..."
  # --fail: sem ele, um HTTP 404/500 grava o corpo do erro e retorna 0 — o
  # teste -f da próxima rodada passaria e o firmware quebrado iria pro build.
  curl --fail -L -o extra_firmware/mrvl/sd8897_uapsta.bin \
    "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mrvl/sd8897_uapsta.bin" \
    && [ -s extra_firmware/mrvl/sd8897_uapsta.bin ] || {
      echo "❌ ERRO FATAL: download de sd8897_uapsta.bin falhou ou gerou arquivo vazio."
      rm -f extra_firmware/mrvl/sd8897_uapsta.bin
      exit 1
    }
fi

if [ ! -f "extra_firmware/mrvl/sd8797_uapsta.bin" ]; then
  # Copiar do diretório do projeto se disponível
  if [ -f "$SCRIPT_DIR/extra_firmware/mrvl/sd8797_uapsta.bin" ]; then
    echo "Copiando sd8797_uapsta.bin do projeto..."
    cp "$SCRIPT_DIR/extra_firmware/mrvl/sd8797_uapsta.bin" extra_firmware/mrvl/
  fi
fi

if [ ! -f "extra_firmware/mrvl/sd8797_uapsta.bin" ]; then
  echo ""
  echo "============================================"
  echo "ATENÇÃO: sd8797_uapsta.bin (Orbis custom) NÃO encontrado!"
  echo "Este firmware é EXIGIDO (CONFIG_EXTRA_FIRMWARE) mesmo para Baikal."
  echo "Opções:"
  echo "  1) Obter do PS4 dev Discord / ps4linux.com / extrair do NOR"
  echo "  2) Colocar manualmente em extra_firmware/mrvl/sd8797_uapsta.bin"
  echo "  3) Desabilitar MWIFIEX_SDIO no config (perde WiFi Aeolia/Belize)"
  echo "============================================"
  echo ""
  read -p "Deseja continuar e desabilitar MWIFIEX_SDIO? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Desabilitando CONFIG_MWIFIEX_SDIO..."
    scripts/config --disable CONFIG_MWIFIEX_SDIO 2>/dev/null || true
  else
    echo "Build cancelado. Coloque o firmware e tente novamente."
    exit 1
  fi
fi

# Firmware MediaTek MT7668 (Baikal WiFi/BT)
if [ ! -f "extra_firmware/mediatek/mt7668pr2h.bin" ]; then
  echo "Baixando mt7668pr2h.bin..."
  curl --fail -L -o extra_firmware/mediatek/mt7668pr2h.bin \
    "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/mt7668pr2h.bin" \
    && [ -s extra_firmware/mediatek/mt7668pr2h.bin ] || {
      echo "❌ ERRO FATAL: download de mt7668pr2h.bin falhou ou gerou arquivo vazio."
      rm -f extra_firmware/mediatek/mt7668pr2h.bin
      exit 1
    }
fi

# Firmware AMD GPU gladius: NÃO embutir no kernel (CONFIG_EXTRA_FIRMWARE).
# O payload kexec (ps4-linux-payloads/linux/ps4-kexec-common/firmware.c)
# já extrai o firmware gladius REAL da RAM do Orbis a cada boot e o
# prepende ao initramfs em lib/firmware/amdgpu/gladius_*.bin. Firmware
# embutido no kernel via CONFIG_EXTRA_FIRMWARE tem prioridade sobre o que
# vem pelo initramfs (fw_get_builtin_firmware roda antes da busca em
# filesystem) — por isso os testes anteriores com gladius=cópia-de-liverpool
# embutido nunca deixavam o kexec entregar o firmware real. Ver
# firmware_gpu/README.md e distros/arch_minimal_v2/TENTATIVAS_7.0.md.

echo "=== Configurando build para Baikal ==="
cd "$KERNEL_SRC_DIR"

# Mover config base, em ordem de preferência:
#  1. Referência histórica 20260720-sky2len-fix em distro/boot_referencia/ — PERDIDA
#     em 2026-11-11 (ver nota "ESTADO DOS
#     ARTEFATOS" no AGENTS.md); mantida aqui caso ressurja de algum backup.
#  2. Config versionada distro/RELEASE/v1.0.0/ (origem 20260801-kvm-rtc-sata-final)
#     — única garantida de existir num clone novo, por estar no git.
#  3. 'config' na raiz da árvore, ou '.config' existente (build incremental).
if [ -f "$BOOT_DIR/config-7.0-20260720-sky2len-fix" ]; then
  echo "Usando config de referência 20260720-sky2len-fix..."
  cp -f "$BOOT_DIR/config-7.0-20260720-sky2len-fix" .config
elif [ -f "$DISTRO_DIR/RELEASE/v1.0.0/config-7.0-v1.0.0" ]; then
  echo "Usando config versionada distro/RELEASE/v1.0.0 (fallback — baselines 202607* perdidas)..."
  cp -f "$DISTRO_DIR/RELEASE/v1.0.0/config-7.0-v1.0.0" .config
elif [ -f "config" ]; then
  mv -f config .config
elif [ -f ".config" ]; then
  echo "Reaproveitando .config existente (build incremental)..."
else
  echo "ERRO: nem 'config' nem '.config' encontrados na raiz do kernel"
  exit 1
fi

# Aplicar configurações específicas Baikal via scripts/config
echo "Aplicando configurações Baikal..."

# Ethernet Baikal GBE (00:14.1, PCI 104d:90d8): NÃO é Synopsys/stmmac!
# DESCOBERTA 2026-07-17 (teste real, tag 20260717-manualeth0): forçar o
# stmmac a abrir essa interface gera Oops real — dwmac4_dma_reset() lê
# offset 0x1000, fora do BAR0 de 4KB ("BUG: unable to handle page fault"),
# e o sistema trava com IRQs desabilitadas. O hardware é na verdade um
# Marvell Yukon 2 (sky2), igual ao Aeolia (0x909e) e Belize (0x90c9) que
# a fail0verflow já suportava neste fork — só faltava o ID do Baikal
# (0x90d8) e o roteamento de IRQ via bpcie (em vez de apcie), replicando
# o padrão do xhci-aeolia.c. Fix em patches/sky2-baikal-gbe.patch.
# A leitura do MAC address via SPM (função MEM 00:14.6, BAR5 + 0x2f000)
# funciona sem mudanças: os offsets Aeolia e Baikal são idênticos.
# stmmac desabilitado — abordagem descartada (histórico: TENTATIVAS_7.0.md
# itens 9-11 e patches/stmmac-baikal-fixedlink.patch, não mais aplicado).
scripts/config --disable CONFIG_NET_VENDOR_STMICRO
scripts/config --disable CONFIG_STMMAC_ETH
scripts/config --disable CONFIG_STMMAC_PCI
scripts/config --disable CONFIG_STMMAC_PLATFORM
scripts/config --disable CONFIG_DWMAC_GENERIC

# Patches PS4 versionados em patches/ — aplicação idempotente via git apply.
# - sky2-baikal-gbe.patch: ID PCI da GBE Baikal + IRQs via bpcie no sky2.
# - ps4-icc-proc-debug.patch: /proc/ps4_icc pra enviar comandos ICC
#   arbitrários ao vivo (mapear o serviço device-power que liga a GBE —
#   syscon mantém "gbe off" por padrão, por isso o Yukon lê chip id 0x0).
# - mts-baikal-kconfig.patch: Kconfig/Makefile do vendor Sony + driver MTS.
#   O driver `mts.c`/`mts.h` vem de `drivers_mts/` (fonte única autoritativa).
#   Ver drivers_mts/README.md, drivers_mts/MTS_INIT_SEQUENCE_dc5a31f0.md.
if [ ! -d "drivers/net/ethernet/sony" ]; then
  for P in ps4-icc-proc-debug.patch mts-baikal-kconfig.patch; do
    PATCH="$SCRIPT_DIR/patches/$P"
    if [ ! -f "$PATCH" ]; then
      echo "❌ ERRO FATAL: $PATCH não encontrado."
      exit 1
    fi
    echo "Aplicando patch $P..."
    if ! git apply --check "$PATCH" 2>/tmp/mts_patch_check.log; then
      echo "❌ ERRO FATAL: patch $P não aplica contra o kernel atual:"
      cat /tmp/mts_patch_check.log
      echo ""
      echo "  Regenere o patch a partir de uma árvore limpa (ver AGENTS.md,"
      echo "  seção 'Idempotência de Alterações no Kernel') e substitua $PATCH."
      exit 1
    fi
    git apply "$PATCH"
    echo "✓ Patch $P aplicado com sucesso (git apply, validado com --check)"
  done
fi

# drivers_mts/ é a fonte única autoritativa do driver MTS (mts.c, mts.h).
# O patch mts-baikal-kconfig.patch contém apenas Kconfig/Makefile do vendor Sony.
# Isso elimina ~3.200 linhas duplicadas e evita divergência patch ↔ source.
echo "Copiando driver MTS autoritativo de drivers_mts/ para a árvore do kernel..."
mkdir -p "drivers/net/ethernet/sony"
cp -f "$SCRIPT_DIR/drivers_mts/mts.c" "drivers/net/ethernet/sony/mts.c"
cp -f "$SCRIPT_DIR/drivers_mts/mts.h" "drivers/net/ethernet/sony/mts.h"
# Kconfig/Makefile do vendor Sony já foram aplicados via patch acima.
# Se drivers_mts/ tiver Kconfig/Makefile próprios, eles são ignorados (patch já fez).
echo "✓ Driver MTS copiado de drivers_mts/ (fonte única)"

# RTC via ICC: wrapper ps4_icc_rtc_cmd() com retry loop (100x50ms) em
# ps4-bpcie-icc.c + declaração em baikal.h/aeolia.h + Kconfig/Makefile +
# drivers/rtc/rtc-ps4-icc.c inteiro — tudo num único patch (fonte única,
# ver comentário mais acima sobre o heredoc/sed removidos). Mesmo padrão
# rigoroso do patch AHCI: `--check` antes, `exit 1` se falhar — nunca
# `|| echo AVISO` (isso já escondeu uma falha real: o patch não aplicava
# por conflito com o heredoc/sed antigos, e o build seguia com
# ps4_icc_rtc_cmd indefinido, sem ninguém perceber).
# Veja consolidado/plans/rtc_via_icc_plan.md (RE 2026-07-25).
PATCH_RTC="$SCRIPT_DIR/patches/ps4-icc-rtc-wrapper.patch"
if [ ! -f "$PATCH_RTC" ]; then
  echo "❌ ERRO FATAL: $PATCH_RTC não encontrado"
  echo "  RTC via ICC não vai compilar sem este patch."
  exit 1
fi

if ! git apply --check "$PATCH_RTC" 2>/tmp/rtc_patch_check.log; then
  echo "❌ ERRO FATAL: patch RTC wrapper não aplica contra o kernel atual:"
  cat /tmp/rtc_patch_check.log
  echo ""
  echo "  Regenere o patch: edite os arquivos, valide com"
  echo "  'make drivers/ps4/ps4-bpcie-icc.o drivers/rtc/rtc-ps4-icc.o', depois"
  echo "  'git diff HEAD -- drivers/ps4/ drivers/rtc/' e substitua $PATCH_RTC."
  exit 1
fi

git apply "$PATCH_RTC"
echo "✓ Patch RTC wrapper aplicado com sucesso (git apply, validado com --check)"

# Memória Baikal (SPM/DDR3, 00:14.6): o patch traz o driver inteiro
# (`drivers/misc/baikal-memory.c`: probe com logging da Fase 1, layout de
# leitura da Fase 2, sysfs da Fase 3) e também `drivers/misc/Kconfig` +
# `drivers/misc/Makefile` (símbolo CONFIG_BAIKAL_MEMORY, com o nome corrigido).
# O `config` rastreado NÃO tem esse símbolo, então ele é
# habilitado via `scripts/config` mais abaixo, antes do `olddefconfig`;
# sem isso `obj-$(CONFIG_BAIKAL_MEMORY)` fica vazio e o .ko não é gerado.
# Mesmo padrão rigoroso: `--check` antes, `exit 1` se falhar — nunca
# `|| echo AVISO`.
PATCH_BAIKAL_MEM="$SCRIPT_DIR/patches/baikal-memory-fase2.patch"
if [ ! -f "$PATCH_BAIKAL_MEM" ]; then
  echo "❌ ERRO FATAL: $PATCH_BAIKAL_MEM não encontrado"
  echo "  Sem ele o build perde as correções do driver baikal-memory."
  exit 1
fi

if ! git apply --check "$PATCH_BAIKAL_MEM" 2>/tmp/baikal_mem_patch_check.log; then
  echo "❌ ERRO FATAL: patch baikal-memory não aplica contra o kernel atual:"
  cat /tmp/baikal_mem_patch_check.log
  echo ""
  echo "  Regenere o patch a partir de uma árvore limpa (ver AGENTS.md,"
  echo "  seção 'Idempotência de Alterações no Kernel') e substitua $PATCH_BAIKAL_MEM."
  exit 1
fi

git apply "$PATCH_BAIKAL_MEM"
echo "✓ Patch baikal-memory aplicado com sucesso (git apply, validado com --check)"

# Controladores DMA do Baikal (00:14.5): driver dmaengine `baikal-dmac`.
# O patch traz drivers/dma/baikal-dmac.c (arquivo novo) + Kconfig + Makefile.
# O driver é módulo (CONFIG_BAIKAL_DMAC=m); o núcleo do dmaengine
# (DMA_ENGINE, DMA_VIRTUAL_CHANNELS) é habilitado via `scripts/config` mais
# abaixo, antes do `olddefconfig`. Mesmo padrão rigoroso: `--check` antes,
# `exit 1` se falhar — nunca `|| echo AVISO`.
PATCH_BAIKAL_DMAC="$SCRIPT_DIR/patches/baikal-dmac.patch"
if [ ! -f "$PATCH_BAIKAL_DMAC" ]; then
  echo "❌ ERRO FATAL: $PATCH_BAIKAL_DMAC não encontrado"
  echo "  Sem ele o build perde o driver dmaengine baikal-dmac."
  exit 1
fi

if ! git apply --check "$PATCH_BAIKAL_DMAC" 2>/tmp/baikal_dmac_patch_check.log; then
  echo "❌ ERRO FATAL: patch baikal-dmac não aplica contra o kernel atual:"
  cat /tmp/baikal_dmac_patch_check.log
  echo ""
  echo "  Regenere o patch a partir de uma árvore limpa (ver AGENTS.md,"
  echo "  seção 'Idempotência de Alterações no Kernel') e substitua $PATCH_BAIKAL_DMAC."
  exit 1
fi

git apply "$PATCH_BAIKAL_DMAC"
echo "✓ Patch baikal-dmac aplicado com sucesso (git apply, validado com --check)"

# HPET clocksource + watchdog do Baikal: os dois patches existiam em patches/ mas
# NUNCA eram aplicados por este script — o código só entrava na árvore porque
# estava commitado nela (commits locais), o que quebra a idempotência: uma
# árvore recém resetada ficava sem os drivers. Agora aplicados aqui, mesmo
# padrão: `--check` antes, `exit 1` se falhar, nunca `|| echo AVISO`.
for P in clocksource-baikal-hpet.patch baikal-wdt.patch; do
  PATCH="$SCRIPT_DIR/patches/$P"
  [ -f "$PATCH" ] || { echo "❌ ERRO FATAL: $PATCH não encontrado"; exit 1; }
  if ! git apply --check "$PATCH" 2>/tmp/baikal_hpet_wdt_patch_check.log; then
    echo "❌ ERRO FATAL: patch $P não aplica contra o kernel atual:"
    cat /tmp/baikal_hpet_wdt_patch_check.log
    echo "  Regenere o patch a partir de uma árvore limpa (ver AGENTS.md)."
    exit 1
  fi
  git apply "$PATCH"
  echo "✓ Patch $P aplicado com sucesso (git apply, validado com --check)"
done

# Ponte de vídeo Panasonic MN864729 (ps4_bridge.c): init do lado DP (MN864729 sink side).
# O bloco estava em #if 0 com comentário "No idea. DP stuff probably. This borks for some reason".
# Habilitando para configurar os registradores DP da ponte ANTES do link training.
# Mesmo padrão: --check antes, exit 1 se falhar.
PATCH_BRIDGE_DP_INIT="$SCRIPT_DIR/patches/ps4-bridge-dp-init.patch"
[ -f "$PATCH_BRIDGE_DP_INIT" ] || { echo "❌ ERRO FATAL: $PATCH_BRIDGE_DP_INIT não encontrado"; exit 1; }
if ! git apply --check "$PATCH_BRIDGE_DP_INIT" 2>/tmp/bridge_dp_init_patch_check.log; then
  echo "❌ ERRO FATAL: patch ps4-bridge-dp-init não aplica contra o kernel atual:"
  cat /tmp/bridge_dp_init_patch_check.log
  echo "  Regenere o patch a partir de uma árvore limpa (ver AGENTS.md)."
  exit 1
fi
git apply "$PATCH_BRIDGE_DP_INIT"
echo "✓ Patch ps4-bridge-dp-init aplicado com sucesso (git apply, validado com --check)"

# Ponte de vídeo Panasonic MN864729 (ps4_bridge.c): forçar link rate 2.7 Gbps
# se o sink suportar (MAX_LINK_RATE >= 0x0A). O DPCD do sink PS4 reporta 5.4 Gbps
# (0x14), mas o amdgpu_atombios_dp_get_dp_link_config escolhe 162000 por ser o
# primeiro que satisfaz o pixel clock. Sobrescrevemos para 270000 no pre_enable
# para melhor margem de clock recovery. Passo 2 do plano DP.
PATCH_BRIDGE_LINK_RATE="$SCRIPT_DIR/patches/ps4-bridge-link-rate.patch"
[ -f "$PATCH_BRIDGE_LINK_RATE" ] || { echo "❌ ERRO FATAL: $PATCH_BRIDGE_LINK_RATE não encontrado"; exit 1; }
if ! git apply --check "$PATCH_BRIDGE_LINK_RATE" 2>/tmp/bridge_link_rate_patch_check.log; then
  echo "❌ ERRO FATAL: patch ps4-bridge-link-rate não aplica contra o kernel atual:"
  cat /tmp/bridge_link_rate_patch_check.log
  echo "  Regenere o patch a partir de uma árvore limpa (ver AGENTS.md)."
  exit 1
fi
git apply "$PATCH_BRIDGE_LINK_RATE"
echo "✓ Patch ps4-bridge-link-rate aplicado com sucesso (git apply, validado com --check)"

# Ponte de vídeo Panasonic MN864729 (ps4_bridge.c): não zerar mn_bridge->mode no
# post_disable. Um DPMS off->on (screensaver) religa o encoder sem novo modeset,
# então ps4_bridge_mode_set não roda e ps4_bridge_enable falhava com
# "mode not available", deixando a ponte resetada e a tela preta (reproduzido
# ao vivo em 2026-11-16, 3/3 ciclos). Mesmo padrão: --check antes, exit 1 se falhar.
PATCH_BRIDGE_KEEP="$SCRIPT_DIR/patches/ps4-bridge-keep-mode.patch"
[ -f "$PATCH_BRIDGE_KEEP" ] || { echo "❌ ERRO FATAL: $PATCH_BRIDGE_KEEP não encontrado"; exit 1; }
if ! git apply --check "$PATCH_BRIDGE_KEEP" 2>/tmp/bridge_keep_patch_check.log; then
  echo "❌ ERRO FATAL: patch ps4-bridge-keep-mode não aplica contra o kernel atual:"
  cat /tmp/bridge_keep_patch_check.log
  echo "  Regenere o patch a partir de uma árvore limpa (ver AGENTS.md)."
  exit 1
fi
git apply "$PATCH_BRIDGE_KEEP"
echo "✓ Patch ps4-bridge-keep-mode aplicado com sucesso (git apply, validado com --check)"

# build.sh (upstream rmuxnet/linux) NÃO é mais usado — em 2026-07-22 seu perfil
# "General/ThinLTO/Baikal" (--option 3 use=General lto=ThinLTO southbridge=Baikal)
# foi incorporado diretamente neste script, para haver um único lugar decidindo a
# config. Removido do checkout para não sobrar um segundo script fazendo build
# "por trás" deste; como é parte do repo upstream, reaparece a cada
# `git reset --hard`, e por isso é apagado de novo a cada build.
#
# Nota histórica: o motivo original de encarar o build.sh foi ele reforçar
# CONFIG_DEBUG_INFO_BTF=y no próprio olddefconfig, depois do nosso --disable.
# Isso hoje é irrelevante — QUEREMOS o BTF ligado; era o nosso --disable que
# estava errado e quebrava o boot. A incorporação continua valendo pela clareza
# de ter uma única fonte de config, não por causa do BTF.
rm -f build.sh

# MediaTek MT7668 WiFi/BT (SDIO)
scripts/config --enable CONFIG_MT76_SDIO
scripts/config --enable CONFIG_MT7668
scripts/config --enable CONFIG_BT_MTKSDIO

# AMD GPU (Gladius CIK)
scripts/config --enable CONFIG_DRM_AMDGPU
scripts/config --enable CONFIG_DRM_AMDGPU_CIK
scripts/config --enable CONFIG_DRM_AMDGPU_USERPTR

# Ethernet Baikal (GbE via Marvell sky2) - EMBUTIDO (=y), não módulo
# Necessário para netconsole funcionar antes do rootfs montar (igual ao kernel 5.4 neocine)
#
# NOTA 2026-07-22: o sky2 NÃO atende a GBE do Baikal — medimos que o hardware é
# um MTS (Orbis usa `mts`/if_mts.c para Baikal e `msk`/Yukon só para
# Aeolia/Belize). Mantido habilitado porque é inofensivo (falha limpa no probe
# com "unsupported chip type 0x0") e ainda serve Aeolia/Belize.
scripts/config --enable CONFIG_SKY2
scripts/config --disable CONFIG_SKY2_DEBUG

# Driver MTS — a GBE real do Baikal. MÓDULO (=m) de propósito: assim o bring-up
# pode ser testado com `insmod mts.ko stage=N` sem arriscar o boot, e um
# estágio ruim não impede o console de subir. Ver o comentário do patch acima.
scripts/config --enable CONFIG_NET_VENDOR_SONY
scripts/config --module CONFIG_MTS_GBE

# Netconsole embutido (=y) para capturar log de boot via UDP
scripts/config --enable CONFIG_NETCONSOLE
scripts/config --enable CONFIG_NETCONSOLE_DYNAMIC

# ZRAM/ZSWAP
scripts/config --enable CONFIG_ZRAM
scripts/config --enable CONFIG_ZSWAP
scripts/config --set-str CONFIG_ZSWAP_COMPRESSOR_DEFAULT "zstd"
scripts/config --set-str CONFIG_ZRAM_DEF_COMP "zstd"

# CPU freq / DPM - testar habilitado
scripts/config --enable CONFIG_X86_AMD_PSTATE
scripts/config --set-val CONFIG_X86_AMD_PSTATE_DEFAULT_MODE 3
scripts/config --enable CONFIG_X86_ACPI_CPUFREQ   # driver ACPI legado para Jaguar (fallback)

# Mitigations off
scripts/config --disable CONFIG_CPU_MITIGATIONS

# Transparent hugepages
scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE
scripts/config --disable CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS
scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE_MADVISE

# Systemd cgroups v1 compat
scripts/config --disable CONFIG_CGROUP_V2
scripts/config --enable CONFIG_CGROUP_LEGACY

# Local version
scripts/config --disable CONFIG_LOCALVERSION_AUTO
scripts/config --set-str CONFIG_LOCALVERSION "-Strawberry-ThinLTO-Baikal-"

# Kernel compression
scripts/config --disable CONFIG_KERNEL_XZ
scripts/config --enable CONFIG_KERNEL_ZSTD

# NUMA off (PS4 tem UMA)
scripts/config --disable CONFIG_NUMA
scripts/config --disable CONFIG_AMD_NUMA
scripts/config --disable CONFIG_X86_64_ACPI_NUMA
scripts/config --disable CONFIG_ACPI_NUMA
scripts/config --disable CONFIG_NUMA_MEMBLKS
scripts/config --disable CONFIG_NUMA_BALANCING

# Hypervisor/VM off
scripts/config --disable CONFIG_HYPERVISOR_GUEST
scripts/config --disable CONFIG_PARAVIRT
scripts/config --disable CONFIG_PARAVIRT_XXL
# scripts/config --disable CONFIG_KVM
# scripts/config --disable CONFIG_KVM_AMD
scripts/config --disable CONFIG_KVM_INTEL

# PS4 specific
scripts/config --enable CONFIG_PS4_DMI_SPOOF
scripts/config --enable CONFIG_X86_PS4_BAIKAL
scripts/config --enable CONFIG_MFD_SYSCON
scripts/config --enable CONFIG_REGMAP_MMIO

# Extra firmware dir
scripts/config --set-str CONFIG_EXTRA_FIRMWARE_DIR "extra_firmware"

# Garantir firmware no built-in:
#  - AMD GPU gladius: propositalmente OMITIDO — ver comentário acima. O
#    driver (CONFIG_DRM_AMDGPU=y, builtin) vai cair no request_firmware()
#    via filesystem, que acha o gladius real dentro do initramfs injetado
#    pelo kexec.
#  - Marvell WiFi (Aeolia/Belize) + MediaTek MT7668 completo (Baikal) — replicando o que o 5.4 neocine embutia p/ WiFi funcionar
scripts/config --set-str CONFIG_EXTRA_FIRMWARE "$EXTRA_FIRMWARE_LIST"
# A existência de todos esses arquivos já foi validada no preflight (antes do
# reset) — o `git clean -e extra_firmware` preserva o diretório.

# --- Perfil General + ThinLTO + Baikal, incorporado do build.sh upstream em
# 2026-07-22 (ver comentário do `rm -f build.sh` acima). Fixo — este projeto
# só builda essa combinação, então não precisamos do menu/parsing de opções
# do build.sh original, só do resultado final que ele aplicava.

# LTO: ThinLTO (nunca FullLTO/none neste projeto)
scripts/config --enable  CONFIG_LTO_CLANG_THIN
scripts/config --disable CONFIG_LTO_CLANG_FULL

# Cgroups (base p/ systemd/containers)
scripts/config --enable  CONFIG_CGROUPS
scripts/config --enable  CONFIG_MEMCG
scripts/config --enable  CONFIG_BLK_CGROUP
scripts/config --enable  CONFIG_CGROUP_WRITEBACK
scripts/config --enable  CONFIG_CGROUP_SCHED
scripts/config --enable  CONFIG_FAIR_GROUP_SCHED
scripts/config --disable CONFIG_RT_GROUP_SCHED
scripts/config --enable  CONFIG_CFS_BANDWIDTH
scripts/config --enable  CONFIG_CGROUP_PIDS
scripts/config --enable  CONFIG_LRU_GEN
scripts/config --enable  CONFIG_LRU_GEN_ENABLED
scripts/config --enable  CONFIG_LRU_GEN_STATS
scripts/config --enable  CONFIG_SLUB_CPU_PARTIAL
scripts/config --enable  CONFIG_CGROUP_DMEM
scripts/config --enable  CONFIG_CGROUP_FREEZER
scripts/config --enable  CONFIG_CPUSETS
scripts/config --enable  CONFIG_CGROUP_DEVICE
scripts/config --enable  CONFIG_CGROUP_CPUACCT
scripts/config --enable  CONFIG_CGROUP_MISC
scripts/config --enable  CONFIG_CGROUP_BPF

# Namespaces (exigido por systemd/container userspace)
scripts/config --enable  CONFIG_NAMESPACES
scripts/config --enable  CONFIG_UTS_NS
scripts/config --enable  CONFIG_TIME_NS
scripts/config --enable  CONFIG_IPC_NS
scripts/config --enable  CONFIG_USER_NS
scripts/config --enable  CONFIG_PID_NS
scripts/config --enable  CONFIG_NET_NS

# ZRAM/ZSWAP: garantir zstd como algoritmo (bool + string)
scripts/config --disable CONFIG_ZSWAP_COMPRESSOR_DEFAULT_LZO
scripts/config --enable  CONFIG_ZSWAP_COMPRESSOR_DEFAULT_ZSTD
scripts/config --disable CONFIG_ZRAM_DEF_COMP_LZ4
scripts/config --enable  CONFIG_ZRAM_DEF_COMP_ZSTD

# Async I/O
scripts/config --enable  CONFIG_IO_URING

# Arquivos em rede: cliente CIFS/SMB (share [dados_aux] do adsv2)
# Módulo (=m), NAO built-in: o bzImage ja esta em ~16 MiB (acima do aviso de
# ~10 MB do loader kexec do PS4) e o distro/01-build-image-7.0.sh faz
# modules_install no rootfs, entao cifs.ko entra em /lib/modules/<kver>.
# CONFIG_MODVERSIONS e CONFIG_MODULE_SIG estao desligados nesta config, logo o
# mesmo cifs.ko tambem carrega no kernel ja em execucao (mesma UTS_RELEASE).
# Ver others/docs/BACKLOG.md, item "Habilitar o cliente CIFS/SMB".
scripts/config --module CONFIG_CIFS
scripts/config --enable CONFIG_CIFS_XATTR   # xattrs (usado pelo Samba)
scripts/config --enable CONFIG_CIFS_POSIX   # extensoes POSIX: modo/ACL

# Rede: BBR + fq
scripts/config --enable  CONFIG_TCP_CONG_BBR
scripts/config --set-str CONFIG_DEFAULT_TCP_CONG "bbr"
scripts/config --enable  CONFIG_NET_SCH_DEFAULT
scripts/config --enable  CONFIG_NET_SCH_FQ
scripts/config --enable  CONFIG_NET_SCH_FQ_CODEL
scripts/config --enable  CONFIG_NET_SCH_CAKE

# Aceleração de cripto (AES-NI etc)
scripts/config --enable  CONFIG_CRYPTO_AES_NI_INTEL
scripts/config --enable  CONFIG_CRYPTO_GHASH_CLMUL_NI_INTEL
scripts/config --enable  CONFIG_CRYPTO_POLYVAL_CLMUL_NI
scripts/config --enable  CONFIG_CRYPTO_LIB_SHA256
scripts/config --enable  CONFIG_CRYPTO_USER   # evita falha do systemd-modules-load (crypto_user)

# Futex / NTSYNC (Proton/Wine)
scripts/config --enable  CONFIG_FUTEX
scripts/config --enable  CONFIG_FUTEX_PI
scripts/config --enable  CONFIG_FUTEX_PRIVATE_HASH
scripts/config --enable  CONFIG_FUTEX_MPOL
scripts/config --enable  CONFIG_NTSYNC

# Scheduler
#
# CONFIG_SCHED_CLASS_EXT depende de DEBUG_INFO_BTF
# (kernel/Kconfig.preempt: "depends on BPF_SYSCALL && BPF_JIT && DEBUG_INFO_BTF"),
# que mantemos LIGADO — então estes --enable pegam de verdade. Ambos estão
# ativos nos kernels que comprovadamente bootam. Se algum dia o BTF for
# desligado, o sched_ext cai junto silenciosamente; é mais um motivo para não
# desligá-lo (ver seção DEBUG_INFO).
scripts/config --enable  CONFIG_SCHED_CLASS_EXT
scripts/config --enable  CONFIG_SCHED_EXT
scripts/config --enable  CONFIG_SCHED_AUTOGROUP

# BPF (JIT sempre ligado; BTF ligado na seção DEBUG_INFO, então CO-RE disponível)
scripts/config --enable  CONFIG_BPF_SYSCALL
scripts/config --enable  CONFIG_BPF_JIT
scripts/config --enable  CONFIG_BPF_JIT_ALWAYS_ON
scripts/config --enable  CONFIG_BPF_JIT_DEFAULT_ON
scripts/config --disable CONFIG_BPF_UNPRIV_DEFAULT_OFF

# DEBUG_INFO: BTF LIGADO — obrigatório para o kernel bootar neste console.
#
# HISTÓRICO (2026-07-22): o BTF foi desabilitado aqui para evitar um OOM do
# pahole. Isso QUEBROU O BOOT: dois builds limpos, sem nenhum código de risco
# (`20260722-gbe-revertido` e `20260722-mts-clean`), deram TELA PRETA, enquanto
# todo build com BTF ligado e sem código arriscado boota normalmente. A seção
# `.BTF` responde por 9,2 MB do vmlinux (medido com readelf), e desabilitá-la
# também derruba CONFIG_SCHED_CLASS_EXT/EXT_GROUP_SCHED por dependência
# (kernel/Kconfig.preempt) — ~60 KB de .text a menos. NÃO DESABILITAR DE NOVO.
#
# O OOM que motivou a remoção era circunstancial: o pahole rodava com -j8 (herda
# o -j do make) enquanto uma VM libvirt ocupava 6 GB da máquina. A solução certa
# é limitar o paralelismo do pahole (JOBS=2 em MAKE_OPTS abaixo), não remover o
# BTF. Ver memory/regressao-build-kernel-desde-2026-07-20.md.
scripts/config --enable  CONFIG_DEBUG_INFO
scripts/config --enable  CONFIG_DEBUG_INFO_DWARF4
scripts/config --disable CONFIG_DEBUG_INFO_DWARF5
scripts/config --disable CONFIG_DEBUG_INFO_REDUCED
scripts/config --disable CONFIG_DEBUG_INFO_SPLIT
scripts/config --disable CONFIG_DEBUG_INFO_BTF
scripts/config --disable CONFIG_DEBUG_INFO_BTF_MODULES

# Debug/tracing em runtime — fora (custo de performance/tamanho, não usamos)
scripts/config --disable CONFIG_DEBUG_KERNEL
scripts/config --disable CONFIG_PROVE_LOCKING
scripts/config --disable CONFIG_LOCKDEP
scripts/config --disable CONFIG_KASAN
scripts/config --disable CONFIG_FTRACE
scripts/config --disable CONFIG_SCHED_DEBUG
scripts/config --disable CONFIG_DEBUG_FS

# Hardening trims (perfil "General" prioriza performance sobre hardening)
scripts/config --disable CONFIG_STACKPROTECTOR
scripts/config --disable CONFIG_STACKPROTECTOR_STRONG
scripts/config --disable CONFIG_RANDOMIZE_KSTACK_OFFSET_DEFAULT
scripts/config --disable CONFIG_SLAB_FREELIST_HARDENED
scripts/config --disable CONFIG_SLAB_FREELIST_RANDOM
scripts/config --disable CONFIG_SHUFFLE_PAGE_ALLOCATOR
scripts/config --disable CONFIG_INIT_ON_ALLOC_DEFAULT_ON
scripts/config --disable CONFIG_INIT_ON_FREE_DEFAULT_ON
scripts/config --disable CONFIG_FORTIFY_SOURCE
scripts/config --disable CONFIG_HARDENED_USERCOPY
scripts/config --disable CONFIG_HARDENED_USERCOPY_DEFAULT_ON
scripts/config --disable CONFIG_SECURITY_DMESG_RESTRICT
scripts/config --disable CONFIG_IOMMU_DEFAULT_DMA_STRICT
scripts/config --disable CONFIG_IOMMU_DEFAULT_PASSTHROUGH
scripts/config --enable  CONFIG_IOMMU_DEFAULT_DMA_LAZY

# I/O schedulers
scripts/config --enable  CONFIG_MQ_IOSCHED_DEADLINE
scripts/config --enable  CONFIG_MQ_IOSCHED_KYBER
scripts/config --enable  CONFIG_IOSCHED_BFQ
scripts/config --enable  CONFIG_BFQ_GROUP_IOSCHED
scripts/config --enable  CONFIG_BLK_WBT
scripts/config --enable  CONFIG_BLK_WBT_MQ

# Tira overhead de debug de subsistemas que não usamos
scripts/config --disable CONFIG_DMADEVICES_DEBUG
scripts/config --disable CONFIG_DMADEVICES_VDEBUG
scripts/config --disable CONFIG_IOMMU_DEBUG
scripts/config --disable CONFIG_I2C_DEBUG_CORE
scripts/config --disable CONFIG_I2C_DEBUG_ALGO
scripts/config --disable CONFIG_I2C_DEBUG_BUS
scripts/config --disable CONFIG_DM_DEBUG
scripts/config --disable CONFIG_BLK_DEBUG_FS

# Perfil "General" (gaming/desktop) — nunca usamos o perfil "Server"
scripts/config --enable  CONFIG_DMIID
scripts/config --enable  CONFIG_DMI_SYSFS
scripts/config --enable  CONFIG_FW_CFG_SYSFS

scripts/config --enable  CONFIG_CPU_FREQ_GOV_REFLEX
scripts/config --enable  CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL
scripts/config --enable  CONFIG_CPU_FREQ_GOV_SCHEDUTIL
scripts/config --disable CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE

scripts/config --enable  CONFIG_HZ_250
scripts/config --disable CONFIG_HZ_300
scripts/config --disable CONFIG_HZ_100
scripts/config --disable CONFIG_HZ_1000
scripts/config --set-val CONFIG_HZ 250
scripts/config --enable  CONFIG_NO_HZ_IDLE
scripts/config --enable  CONFIG_NO_HZ_FULL
scripts/config --enable  CONFIG_RCU_NOCB_CPU
scripts/config --enable  CONFIG_RCU_NOCB_CPU_DEFAULT_ALL

scripts/config --enable  CONFIG_PREEMPT
scripts/config --disable CONFIG_PREEMPT_VOLUNTARY
scripts/config --disable CONFIG_PREEMPT_NONE

scripts/config --disable CONFIG_OVERLAY_FS
scripts/config --disable CONFIG_VETH
scripts/config --disable CONFIG_BRIDGE_NETFILTER
scripts/config --disable CONFIG_BRIDGE
scripts/config --disable CONFIG_IP6_NF_IPTABLES
scripts/config --disable CONFIG_IP_NF_IPTABLES
scripts/config --disable CONFIG_NF_TABLES_IPV6
scripts/config --disable CONFIG_NF_TABLES_IPV4
scripts/config --disable CONFIG_NF_TABLES_INET
scripts/config --disable CONFIG_NF_TABLES
scripts/config --disable CONFIG_NETFILTER_XTABLES
scripts/config --disable CONFIG_NETFILTER_ADVANCED
scripts/config --disable CONFIG_NETFILTER

scripts/config --disable CONFIG_PSI
scripts/config --set-str CONFIG_DEFAULT_IOSCHED "bfq"

scripts/config --enable  CONFIG_DEFAULT_FQ_CODEL
scripts/config --disable CONFIG_DEFAULT_FQ
scripts/config --disable CONFIG_DEFAULT_FQ_PIE
scripts/config --disable CONFIG_DEFAULT_SFQ
scripts/config --disable CONFIG_DEFAULT_PFIFO_FAST
scripts/config --set-str CONFIG_DEFAULT_NET_SCH "fq_codel"

# RTC: habilitar infraestrutura padrao do Linux para /dev/rtc, /sys/class/rtc e hwclock.
# Suporte real via PS4 ICC (Fase 3 do plano rtc_via_icc_plan.md) implementado em
# drivers/rtc/rtc-ps4-icc.c (2026-07-31) -- ainda PENDENTE de teste ao vivo no
# hardware, ver consolidado/BACKLOG.md. RTC_DRV_CMOS continua habilitado como
# fallback caso o rtc-ps4-icc nao registre /dev/rtc0 corretamente.
scripts/config --enable  CONFIG_RTC_CLASS
# UIE emulation: o rtc-ps4-icc nao tem IRQ de update no hardware. Sem isso o
# `hwclock -r` fica esperando o tick em select() e sai com
# "select() to /dev/rtc to wait for clock tick timed out" (exit 1) mesmo com
# a hora correta no /sys/class/rtc/rtc0. Validado em 2026-11-12.
scripts/config --enable  CONFIG_RTC_INTF_DEV_UIE_EMUL
scripts/config --enable  CONFIG_RTC_INTF_DEV
scripts/config --enable  CONFIG_RTC_INTF_SYSFS
scripts/config --enable  CONFIG_RTC_INTF_PROC
scripts/config --enable  CONFIG_RTC_DRV_CMOS
scripts/config --module  CONFIG_RTC_DRV_PS4_ICC
scripts/config --enable  CONFIG_RTC_HCTOSYS
scripts/config --set-str CONFIG_RTC_HCTOSYS_DEVICE "rtc0"
scripts/config --enable  CONFIG_RTC_SYSTOHC
scripts/config --set-str CONFIG_RTC_SYSTOHC_DEVICE "rtc0"

# KVM-AMD: virtualização por hardware para VMs QEMU (investigação de viabilidade
# completa em PLANO_KVM_PS4_VIABILIDADE_2026-07-24.md). CPU Jaguar expõe SVM/NPT.
# Habilitado em 2026-08-01 para teste prático.
scripts/config --enable  CONFIG_KVM
scripts/config --enable  CONFIG_KVM_AMD

# Memória Baikal (SPM/DDR3, 00:14.6): habilita o módulo, que vem do patch
# aplicado acima (Kconfig/Makefile incluídos nele). Precisa acontecer antes do
# olddefconfig para o símbolo existir no .config resolvido.
scripts/config --module CONFIG_BAIKAL_MEMORY

# DMA dos southbridges Baikal (00:14.5): o núcleo do dmaengine PRECISA ser
# embutido (DMA_ENGINE é bool), senão um módulo externo nem carrega. O driver
# baikal-dmac fica como módulo (iteração de versões sem rebuild do kernel) e o
# dmatest como módulo é a ferramenta padrão para validar um dmaengine.
scripts/config --enable CONFIG_DMA_ENGINE
scripts/config --enable CONFIG_DMA_VIRTUAL_CHANNELS
scripts/config --module CONFIG_BAIKAL_DMAC
scripts/config --module CONFIG_DMATEST

# HPET/Clocksource do Baikal (glue 00:14.4, subfunção ICC 22): clocksource
# baseado no contador principal de 64 bits do HPET. Habilitado como módulo
# para iteração sem rebuild do kernel.
# DESLIGADO por padrão (2026-11-15): CLKSRC_BAIKAL_HPET faz select de CLKSRC_MMIO=y
# (embutido), o que altera o layout do bzImage; junto com o core do WATCHDOG
# coincidiu com 2 boots mortos. Mantém o config idêntico ao do último boot bom
# até o HPET ser testado isoladamente. O patch continua sendo aplicado.
scripts/config --disable CONFIG_CLKSRC_BAIKAL_HPET

# Watchdog do Baikal (Timer 0 do HPET, opcional): requer WATCHDOG_CORE.
# Habilitado como módulo para iteração sem rebuild do kernel.
# ATENÇÃO (2026-11-15): CONFIG_BAIKAL_WDT fica dentro do menu WATCHDOG. Habilitar
# CONFIG_WATCHDOG=y (core embutido) coincidiu com 2 boots mortos no PS4: o log da UART
# para em "kexec: About to relocate and jump to kernel", sem nenhum byte do kernel
# (nem earlycon). Os cabeçalhos do bzImage (init_size/align/pref) eram idênticos aos
# do build que boota; a diferença embutida era só WATCHDOG/WATCHDOG_CORE/CLKSRC_MMIO.
# Por isso o WDT fica DESLIGADO por padrão: o patch ainda é aplicado (idempotência),
# mas o símbolo permanece oculto e o módulo não é compilado até haver teste isolado.
scripts/config --disable CONFIG_WATCHDOG
scripts/config --disable CONFIG_WATCHDOG_CORE

echo "=== Executando olddefconfig ==="
make "${MAKE_OPTS[@]}" olddefconfig

echo "=== Preparando build ==="
make "${MAKE_OPTS[@]}" prepare

echo "=== Compilando kernel (ThinLTO, General profile, Baikal) ==="
# Limita threads do link ThinLTO (ld.lld sem --thinlto-jobs usa todos os
# núcleos e cada thread segura estado do módulo -> OOM real já visto no
# passo LD vmlinux.o, 2026-07-21).
export MAKEFLAGS="${MAKEFLAGS:-} vmlinux-o-ld-args-y=--thinlto-jobs=2"
time make "${MAKE_OPTS[@]}" bzImage

echo "=== Compilando módulos ==="
make "${MAKE_OPTS[@]}" modules

echo "=== Verificando bzImage ==="
BZIMAGE="arch/x86/boot/bzImage"
if [ -f "$BZIMAGE" ]; then
  if [ -f "$OUTPUT_BZIMAGE" ]; then
    echo "Fazendo backup do bzImage atual..."
    cp "$OUTPUT_BZIMAGE" "$OUTPUT_BZIMAGE.bak"
  fi
  cp "$BZIMAGE" "$OUTPUT_BZIMAGE"
  echo "=== Kernel copiado para $OUTPUT_BZIMAGE ==="
  
  # Copiar .config
  cp .config "$OUTPUT_CONFIG"
  echo "=== Config copiada para $OUTPUT_CONFIG ==="
  
  # Mostrar versão
  KVER=$(cat include/config/kernel.release 2>/dev/null || echo "unknown")
  echo "Kernel version: $KVER"
  
  # Tamanho
  ls -lh "$OUTPUT_BZIMAGE"

  # Lição #23 (consolidado/LICOES_APRENDIDAS.md): alguns loaders de kexec do
  # PS4 rejeitam bzImage acima de ~10 MB. Avisar aqui, não no boot.
  BZSIZE="$(stat -c%s "$OUTPUT_BZIMAGE")"
  if [ "$BZSIZE" -gt 10485760 ]; then
    echo "⚠⚠ AVISO: bzImage com $((BZSIZE / 1024 / 1024)) MiB — ACIMA do limite de ~10 MB de alguns loaders kexec do PS4!"
  fi
else
  echo "ERRO: bzImage não encontrado em $BZIMAGE"
  exit 1
fi

# 🔴 SALVAGUARDA (pedida pelo usuário 2026-08-01, ver AGENTS.md "Idempotência
# de Alterações no Kernel"): snapshot bruto da árvore fonte já patcheada,
# capturado logo após um build bem-sucedido — redundante ao mecanismo de
# patches/heredocs em patches/, para o caso de algum patch não cobrir tudo ou
# algum mecanismo falhar silenciosamente sem ninguém perceber. Fica só como
# referência de emergência ("se tudo der errado, temos a fonte exata que
# gerou este bzImage"); não é o mecanismo de reprodutibilidade principal.
echo ""
echo "=== Gerando snapshot de segurança da árvore fonte (pós-build) ==="
# zstd -T0 -9 escolhido sobre xz depois de medir os dois ao vivo nesta árvore
# (2026-08-01): xz -T0 -6 levou 5m48s para 444M, zstd -T0 -9 levou 23s para
# 479M (~8% maior, ~15x mais rápido) — melhor trade-off para rodar em TODO
# build sem virar gargalo perceptível.
mkdir -p "$SNAPSHOT_DIR"
SNAPSHOT_DATE="$(date +%Y%m%d)"
SNAPSHOT_FILE="$SNAPSHOT_DIR/kernel-src-${SNAPSHOT_DATE}-${TAG}.tar.zst"
if tar -I 'zstd -T0 -9' -cf "$SNAPSHOT_FILE" \
    --exclude='*.o' --exclude='*.cmd' --exclude='*.ko' --exclude='*.a' \
    --exclude='*.mod' --exclude='*.mod.c' --exclude='*.symvers' \
    --exclude="$(basename "$KERNEL_SRC_DIR")/vmlinux*" --exclude='System.map' --exclude='.tmp_*' \
    --exclude='include/generated' --exclude='include/config' \
    -C "$(dirname "$KERNEL_SRC_DIR")" "$(basename "$KERNEL_SRC_DIR")" 2>/tmp/snapshot_err.log; then
  echo "✓ Snapshot salvo em $SNAPSHOT_FILE ($(du -h "$SNAPSHOT_FILE" | cut -f1))"
else
  echo "⚠ AVISO: snapshot de segurança falhou (não bloqueia o build, só avisa):"
  cat /tmp/snapshot_err.log
fi

echo ""
echo "=== Build concluído (tag: $TAG) ==="
echo "Arquivos gerados:"
echo "  $OUTPUT_BZIMAGE"
echo "  $OUTPUT_CONFIG"
echo ""
echo "Próximos passos:"
echo "  1. Crie/ajuste /bootargs-7.0-.txt"
echo "  2. sudo $DISTRO_DIR/deploy-boot-7.0.sh $TAG   (só troca o boot no HD já particionado, mantém rootfs)"
echo "     — ou, para gravação completa (particiona e recria rootfs):"
echo "     sudo $DISTRO_DIR/01-build-image-7.0.sh && sudo $DISTRO_DIR/02-burn-image-7.0.sh /dev/sda"