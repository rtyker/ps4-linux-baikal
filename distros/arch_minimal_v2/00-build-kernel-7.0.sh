#!/bin/bash
# 00-build-kernel-7.0.sh — Compila o kernel Strawberry 7.0 para PS4 Baikal
# Script ÚNICO e OFICIAL de build (ThinLTO, General profile, Baikal) — roda
# sem parâmetros. Não depende mais do build.sh do repo upstream (removido do
# fluxo em 2026-07-22, ver comentário mais abaixo perto do `rm -f build.sh`).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_SRC_DIR="/mnt/hdauxiliar/temp/kernel_build_7.0"
REPO_URL="https://github.com/rmuxnet/linux.git"
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
OUTPUT_BZIMAGE="$SCRIPT_DIR/boot_referencia/bzImage-7.0-$TAG"
OUTPUT_CONFIG="$SCRIPT_DIR/boot_referencia/config-7.0-$TAG"

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
export CCACHE_DIR="/mnt/hdauxiliar/ccache"
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
# git reset --hard / git clean -fdx descartam SILENCIOSAMENTE qualquer mudança
# não commitada em arquivos rastreados. Isso já causou perda real de trabalho
# (SATA polling de 2026-07-30, nunca extraído para patches/, perdido no build
# de 2026-08-01). Chamar esta função IMEDIATAMENTE ANTES de cada reset/clean
# real força a extração ANTES da perda. NÃO chamar antes disso — no caminho
# incremental (LOCAL==REMOTE, nenhum reset acontece), os patches já aplicados
# em rodadas anteriores deixam drivers/ata/etc "sujos" de propósito (git apply
# sem commit, por design), e isso é esperado/seguro ali, não motivo de abortar.
abort_if_kernel_tree_dirty() {
  local dirty
  dirty=$(git status --porcelain --untracked-files=no -- drivers/ arch/ include/ 2>/dev/null)
  if [ -n "$dirty" ]; then
    echo ""
    echo "❌ ERRO: mudanças NÃO commitadas detectadas em arquivos rastreados do kernel:"
    echo "$dirty"
    echo ""
    echo "Este comando vai rodar 'git reset --hard'/'git clean -fdx', que APAGA"
    echo "essas mudanças sem aviso. Antes de continuar:"
    echo "  1. Gere um patch real (não escrito à mão):"
    echo "       git diff HEAD -- <arquivos> > $SCRIPT_DIR/patches/<nome>.patch"
    echo "  2. Valide que compila isoladamente:"
    echo "       make CC=\"ccache clang\" LLVM=1 ARCH=x86_64 <arquivo>.o"
    echo "  3. Adicione a aplicação do patch a este script (ver bloco RTC/SATA"
    echo "     como exemplo), para que sobreviva ao próximo reset."
    echo "  4. Só então rode este script de novo."
    echo ""
    echo "Abortando para não repetir a perda de 2026-08-01 (memory/regressao-sata-2026-08-01-diagnostico-e-solucao.md)."
    exit 1
  fi
}

echo "=== Configurando diretório de build ==="
cleanup_build_dir
if [ -d "$KERNEL_SRC_DIR" ]; then
  cd "$KERNEL_SRC_DIR"

  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
  if [ "$CURRENT_BRANCH" = "$BRANCH" ] && [ -f ".config" ] && [ -f "vmlinux" ]; then
    echo "Build anterior encontrado no branch $BRANCH, aproveitando cache..."
    git fetch origin
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse "origin/$BRANCH")
    if [ "$LOCAL" = "$REMOTE" ]; then
      echo "Código já atualizado, build incremental será usado."
    else
      echo "Atualizando para origin/$BRANCH..."
      git merge --ff-only "origin/$BRANCH" || { abort_if_kernel_tree_dirty; git reset --hard "origin/$BRANCH"; }
    fi
  else
    echo "Limpando build anterior (branch ou config diferente)..."
    git fetch origin
    git checkout "$BRANCH"
    abort_if_kernel_tree_dirty
    git reset --hard "origin/$BRANCH"
    git clean -fdx
  fi
else
  echo "Clonando o repositório do kernel..."
  git clone "$REPO_URL" "$KERNEL_SRC_DIR" --depth 1 -b "$BRANCH"
  cd "$KERNEL_SRC_DIR"
fi

# Reconstruir drivers/rtc/rtc-ps4-icc.c (perdido em git reset --hard)
# Este arquivo NÃO é parte do upstream, só do projeto PS4 Linux.
# Copiá-lo aqui garante que não seja perdido após clean/reset.
echo "=== Restaurando drivers PS4 customizados ==="
cat > drivers/rtc/rtc-ps4-icc.c << 'RTCEOF'
// SPDX-License-Identifier: GPL-2.0
/*
 * PS4 RTC driver via ICC (Baikal/Aeolia/Belize)
 *
 * Based on RE of Orbis 12.52 kernel (rtc.c / rtc_mvl.c)
 * Validated 2026-07-25: ICC major=2 minor=0x0b/0x0c (save/load context),
 * major=4 minor=0x50 (alarm bitmask), MMIO 0x5180000/0x5140000.
 *
 * Follows the high-level rtc.c (ICC + MMIO), NOT the low-level rtc_mvl.c
 * which is read-only and uses different MMIO offsets.
 */

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/mod_devicetable.h>
#include <linux/rtc.h>
#include <linux/io.h>
#include <linux/delay.h>
#include <linux/err.h>

extern int ps4_icc_rtc_cmd(u8 major, u16 minor, const void *data, u16 length,
			    void *reply, u16 reply_length);

#define PS4_RTC_MMIO_READ	0x5180000
#define PS4_RTC_MMIO_WRITE	0x5140000
#define PS4_RTC_MMIO_SIZE	8

struct ps4_rtc_softc {
	void __iomem *mmio_read;
	void __iomem *mmio_write;
};

static int ps4_rtc_read_time(struct device *dev, struct rtc_time *tm)
{
	struct ps4_rtc_softc *sc = dev_get_drvdata(dev);
	u8 ctx_loaded = 0;
	u64 mmio_time;
	int rc;

	rc = ps4_icc_rtc_cmd(2, 0x0c, &ctx_loaded, 1, &ctx_loaded, 1);
	if (rc < 0)
		dev_warn(dev, "RTC: icc load context fail %d\n", rc);

	mmio_time = readq(sc->mmio_read);
	rtc_time64_to_tm(mmio_time, tm);
	return 0;
}

static int ps4_rtc_set_time(struct device *dev, struct rtc_time *tm)
{
	struct ps4_rtc_softc *sc = dev_get_drvdata(dev);
	u64 t = rtc_tm_to_time64(tm);
	u8 flag = 1;

	writeq(t, sc->mmio_write);
	ps4_icc_rtc_cmd(2, 0x0b, &flag, 1, &flag, 1);
	return 0;
}

static int ps4_rtc_read_alarm(struct device *dev, struct rtc_wkalrm *alrm)
{
	u8 bitmask = 0;
	int rc;

	rc = ps4_icc_rtc_cmd(4, 0x50, &bitmask, 1, &bitmask, 1);
	if (rc < 0)
		return rc;

	if (bitmask == 0xff) {
		alrm->enabled = 0;
	} else {
		alrm->enabled = !!(bitmask & 0x7);
		alrm->time.tm_sec = 0;
		alrm->time.tm_min = 0;
		alrm->time.tm_hour = 0;
		alrm->time.tm_mday = 1;
		alrm->time.tm_mon = 0;
		alrm->time.tm_year = 70;
	}
	return 0;
}

static int ps4_rtc_set_alarm(struct device *dev, struct rtc_wkalrm *alrm)
{
	u8 new = alrm->enabled ? 0x7 : 0x00;
	int rc;

	rc = ps4_icc_rtc_cmd(4, 0x50, &new, 1, &new, 1);
	return rc;
}

static int ps4_rtc_alarm_irq_enable(struct device *dev, unsigned int enabled)
{
	return 0;
}

static const struct rtc_class_ops ps4_rtc_ops = {
	.read_time		= ps4_rtc_read_time,
	.set_time		= ps4_rtc_set_time,
	.read_alarm		= ps4_rtc_read_alarm,
	.set_alarm		= ps4_rtc_set_alarm,
	.alarm_irq_enable	= ps4_rtc_alarm_irq_enable,
};

static int ps4_rtc_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct ps4_rtc_softc *sc;
	struct rtc_device *rtc;

	sc = devm_kzalloc(dev, sizeof(*sc), GFP_KERNEL);
	if (!sc)
		return -ENOMEM;

	sc->mmio_read = devm_ioremap(dev, PS4_RTC_MMIO_READ, PS4_RTC_MMIO_SIZE);
	if (!sc->mmio_read)
		return -ENXIO;

	sc->mmio_write = devm_ioremap(dev, PS4_RTC_MMIO_WRITE, PS4_RTC_MMIO_SIZE);
	if (!sc->mmio_write)
		return -ENXIO;

	platform_set_drvdata(pdev, sc);

	rtc = devm_rtc_device_register(dev, "ps4-rtc-icc", &ps4_rtc_ops, THIS_MODULE);
	if (IS_ERR(rtc))
		return PTR_ERR(rtc);

	dev_info(dev, "PS4 RTC via ICC registered (mmio_read=0x%lx, mmio_write=0x%lx)\n",
		 (unsigned long)PS4_RTC_MMIO_READ, (unsigned long)PS4_RTC_MMIO_WRITE);

	return 0;
}

static const struct platform_device_id ps4_rtc_id_table[] = {
	{ "ps4-rtc-icc", 0 },
	{ },
};
MODULE_DEVICE_TABLE(platform, ps4_rtc_id_table);

static struct platform_driver ps4_rtc_driver = {
	.driver = {
		.name = "ps4-rtc-icc",
	},
	.probe = ps4_rtc_probe,
	.id_table = ps4_rtc_id_table,
};

static struct platform_device *ps4_rtc_pdev;

static int __init ps4_rtc_init(void)
{
	int ret;

	ps4_rtc_pdev = platform_device_register_simple("ps4-rtc-icc", -1, NULL, 0);
	if (IS_ERR(ps4_rtc_pdev))
		return PTR_ERR(ps4_rtc_pdev);

	ret = platform_driver_register(&ps4_rtc_driver);
	if (ret) {
		platform_device_unregister(ps4_rtc_pdev);
		return ret;
	}

	return 0;
}

static void __exit ps4_rtc_exit(void)
{
	platform_driver_unregister(&ps4_rtc_driver);
	platform_device_unregister(ps4_rtc_pdev);
}

module_init(ps4_rtc_init);
module_exit(ps4_rtc_exit);

MODULE_AUTHOR("PS4 Linux Baikal");
MODULE_DESCRIPTION("PS4 RTC driver via ICC (Baikal/Aeolia/Belize)");
MODULE_LICENSE("GPL");
MODULE_ALIAS("platform:ps4-rtc-icc");
RTCEOF
echo "✓ drivers/rtc/rtc-ps4-icc.c restaurado"

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
  curl -L -o extra_firmware/mrvl/sd8897_uapsta.bin \
    "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mrvl/sd8897_uapsta.bin"
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
  curl -L -o extra_firmware/mediatek/mt7668pr2h.bin \
    "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/mt7668pr2h.bin"
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

# Mover config base (usando a referência sky2len-fix se disponível)
if [ -f "$SCRIPT_DIR/boot_referencia/config-7.0-20260720-sky2len-fix" ]; then
  echo "Usando config de referência 20260720-sky2len-fix..."
  cp -f "$SCRIPT_DIR/boot_referencia/config-7.0-20260720-sky2len-fix" .config
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
# - mts-baikal-gbe-driver.patch: driver `mts` novo para a GBE do Baikal.
#   O Orbis usa `msk`/Yukon para Aeolia/Belize mas `mts` (sys/dev/mts/if_mts.c)
#   para o Baikal — silício diferente, por isso o sky2 nunca ia funcionar aqui.
#   Bring-up em estágios via `mts.stage=N` (default 1 = só dump, não escreve).
#   Ver memory/GBE-VIVA-driver-errado-mts-nao-sky2.md e
#   consolidado/MTS_INIT_SEQUENCE_dc5a31f0.md
if [ -f "drivers/net/ethernet/sony/mts.c" ]; then
  echo "Copiando mts.c e mts.h atualizados para o diretório de build do kernel..."
  cp "$SCRIPT_DIR/../../drivers_mts/mts.c" "drivers/net/ethernet/sony/mts.c"
  cp "$SCRIPT_DIR/../../drivers_mts/mts.h" "drivers/net/ethernet/sony/mts.h"
else
  for P in ps4-icc-proc-debug.patch mts-baikal-gbe-driver.patch; do
    PATCH="$SCRIPT_DIR/patches/$P"
    if [ ! -f "$PATCH" ]; then
      echo "ERRO: $PATCH não encontrado."
      exit 1
    fi
    echo "Aplicando patch $P..."
    git apply "$PATCH"
  done
fi

# Patch Fase 2 do RTC: adiciona wrapper ps4_icc_rtc_cmd() com retry loop
# (100x50ms) em ps4-bpcie-icc.c + declara em baikal.h/aeolia.h. Idempotente.
# Veja consolidado/plans/rtc_via_icc_plan.md (RE 2026-07-25).
PATCH_RTC="$SCRIPT_DIR/patches/ps4-icc-rtc-wrapper.patch"
if [ -f "$PATCH_RTC" ]; then
  echo "Aplicando patch $PATCH_RTC..."
  git apply "$PATCH_RTC" || echo "AVISO: $PATCH_RTC já estava aplicado (idempotente)."
fi

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
scripts/config --disable CONFIG_KVM
scripts/config --disable CONFIG_KVM_AMD
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
scripts/config --set-str CONFIG_EXTRA_FIRMWARE "mrvl/sd8897_uapsta.bin mrvl/sd8797_uapsta.bin mediatek/mt7668pr2h.bin EEPROM_MT7668.bin EEPROM_MT7668_e1.bin mt7668_patch_e1_hdr.bin mt7668_patch_e2_hdr.bin TxPwrLimit_MT76x8.dat wifi.cfg WIFI_RAM_CODE2_SDIO_MT7668.bin WIFI_RAM_CODE2_USB_MT7668.bin WIFI_RAM_CODE_MT7668.bin"

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
scripts/config --enable  CONFIG_DEBUG_INFO_BTF
scripts/config --enable  CONFIG_DEBUG_INFO_BTF_MODULES

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
SNAPSHOT_DIR="/mnt/hdauxiliar/kernel_source_snapshots"
mkdir -p "$SNAPSHOT_DIR"
SNAPSHOT_DATE="$(date +%Y%m%d)"
SNAPSHOT_FILE="$SNAPSHOT_DIR/kernel-src-${SNAPSHOT_DATE}-${TAG}.tar.zst"
if tar -I 'zstd -T0 -9' -cf "$SNAPSHOT_FILE" \
    --exclude='*.o' --exclude='*.cmd' --exclude='*.ko' --exclude='*.a' \
    --exclude='*.mod' --exclude='*.mod.c' --exclude='*.symvers' \
    --exclude='vmlinux*' --exclude='System.map' --exclude='.tmp_*' \
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
echo "  1. Crie/ajuste boot_referencia/bootargs-7.0-$TAG.txt"
echo "  2. sudo ./deploy-boot-7.0.sh $TAG   (só troca o boot no HD já particionado, mantém rootfs)"
echo "     — ou, para gravação completa (particiona e recria rootfs):"
echo "     sudo ./01-build-image-7.0.sh && sudo ./02-burn-image-7.0.sh /dev/sda"