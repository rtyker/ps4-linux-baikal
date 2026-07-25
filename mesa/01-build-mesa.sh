#!/bin/bash
# 01-build-mesa.sh — Build do Mesa customizado para o GPU do PS4 (Liverpool/Gladius)
#
# Baixa o Mesa (versão compatível com o sistema instalado por padrão, ou a mais
# recente com --latest), aplica o patch PS4 Gladius/Liverpool
# (ps4-gladius-liverpool-patch/), compila nativamente (radeonsi + RADV) e
# empacota os artefatos prontos pra deploy via LD_LIBRARY_PATH no PS4.
#
# Uso:
#   ./01-build-mesa.sh                  # versão compatível com o mesa já instalado neste host
#   MESA_VERSION=26.1.5 ./01-build-mesa.sh   # versão específica
#   ./01-build-mesa.sh --latest         # última release estável do Mesa upstream
#
# Requisito de compatibilidade: o build é NATIVO (não cross-compile) — só faz
# sentido rodar num host x86_64 com glibc/libdrm na mesma versão (ou compatível)
# do PS4 alvo. Confirmado em 2026-07-24: host e PS4 rodavam exatamente a mesma
# versão de glibc (2.43+r37) e libdrm (2.4.134), então os .so resultantes
# funcionam por ABI sem cross-compile. Se o PS4 estiver em versão bem diferente,
# builde direto nele (mais lento) ou monte um chroot/container com a mesma libc.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="/mnt/hdauxiliar/temp/mesa_build"
TARBALL_DIR="/mnt/hdauxiliar/temp/sourceballs"
PATCH_DIR="$SCRIPT_DIR/ps4-gladius-liverpool-patch"
PATCH_FILE="$PATCH_DIR/mesa-26.1.5-ps4-gladius-liverpool.patch"
ARTIFACTS_DIR="$SCRIPT_DIR/build_artifacts"

# --- Seleção de versão --------------------------------------------------
resolve_version() {
	if [ -n "${MESA_VERSION:-}" ]; then
		echo "$MESA_VERSION"
		return
	fi
	if [ "${1:-}" = "--latest" ]; then
		# Última tag "mesa-X.Y.Z" do repositório oficial (sem pre-releases rc/beta)
		curl -sL "https://gitlab.freedesktop.org/api/v4/projects/176/repository/tags?order_by=updated&per_page=20" |
			grep -oE '"name":"mesa-[0-9]+\.[0-9]+\.[0-9]+"' |
			grep -voE 'rc|beta' |
			head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' && return
		echo "ERRO: nao consegui consultar a API do GitLab pra achar a ultima versao" >&2
		exit 1
	fi
	# Padrão: versão do Mesa já instalado neste host (== compatibilidade
	# garantida por ABI com o PS4, que roda a mesma base Arch rolling).
	pacman -Q mesa 2>/dev/null | awk '{print $2}' | sed -E 's/^[0-9]+://; s/-[0-9]+$//'
}

MESA_VERSION="$(resolve_version "${1:-}")"
if [ -z "$MESA_VERSION" ]; then
	echo "ERRO: nao foi possivel determinar a versao do Mesa a compilar." >&2
	echo "       Defina MESA_VERSION=X.Y.Z manualmente ou use --latest." >&2
	exit 1
fi

echo "=== Mesa version selecionada: $MESA_VERSION ==="

MESA_SRC_DIR="$BUILD_ROOT/mesa-$MESA_VERSION"
BUILD_DIR="$MESA_SRC_DIR/build"
MESA_TAR="$TARBALL_DIR/mesa-$MESA_VERSION.tar.xz"

mkdir -p "$BUILD_ROOT" "$TARBALL_DIR" "$ARTIFACTS_DIR"

# --- Dependências de build (host) ---------------------------------------
echo "=== Conferindo dependencias de build ==="
pacman -S --needed --noconfirm \
	base-devel meson ninja git pkgconf python python-mako \
	llvm clang libdrm wayland libglvnd libunwind libxml2 libxkbcommon 2>&1 | tail -5

# --- Download (automático se não existir em cache) ----------------------
if [ ! -f "$MESA_TAR" ]; then
	echo "=== Baixando mesa-$MESA_VERSION.tar.xz de archive.mesa3d.org ==="
	curl -fL "https://archive.mesa3d.org/mesa-$MESA_VERSION.tar.xz" -o "$MESA_TAR.tmp"
	mv "$MESA_TAR.tmp" "$MESA_TAR"
else
	echo "=== Usando tarball em cache: $MESA_TAR ==="
fi

# --- Extração -------------------------------------------------------------
if [ ! -d "$MESA_SRC_DIR" ]; then
	echo "=== Extraindo mesa-$MESA_VERSION.tar.xz ==="
	mkdir -p "$MESA_SRC_DIR"
	tar -xf "$MESA_TAR" -C "$BUILD_ROOT"
fi

# --- Aplicação do patch PS4 (idempotente) --------------------------------
echo "=== Aplicando patch PS4 Gladius/Liverpool ==="
cd "$MESA_SRC_DIR"
if patch -p1 --dry-run -R -s < "$PATCH_FILE" >/dev/null 2>&1; then
	echo "  (patch ja aplicado, pulando)"
else
	patch -p1 --verbose < "$PATCH_FILE"
fi

# --- Configuração via Meson ----------------------------------------------
# gallium-drivers=radeonsi e vulkan-drivers=amd sao os unicos drivers
# necessarios para o GPU real do PS4/PS4 Pro (Liverpool/Gladius, familia GCN
# "Sea Islands"/GFX7). NAO usar swrast/virgl/lima/etnaviv/kmsro aqui -- essas
# sao para GPUs ARM embarcadas ou renderizacao por software, irrelevantes pro
# nosso hardware (isso era um bug da versao anterior deste script: sem
# "radeonsi" na lista, o build nem gerava o radeonsi_dri.so).
echo "=== Configurando build com Meson ==="
if [ ! -d "$BUILD_DIR" ]; then
	meson setup "$BUILD_DIR" \
		--buildtype=release \
		-Dgallium-drivers=radeonsi \
		-Dvulkan-drivers=amd \
		-Dplatforms=x11 \
		-Dgles1=disabled \
		-Dgles2=enabled \
		-Dglx=dri \
		-Degl=enabled \
		-Dgbm=enabled \
		-Dllvm=enabled \
		-Dvalgrind=disabled \
		-Db_ndebug=true
else
	echo "  (build dir ja configurado, rode 'meson configure' manualmente se precisar mudar opcoes)"
fi

# --- Compilação -----------------------------------------------------------
echo "=== Compilando com ninja ==="
ninja -C "$BUILD_DIR" -j"$(nproc)"

# --- Empacotamento dos artefatos -------------------------------------------
echo "=== Instalando artefatos para $ARTIFACTS_DIR ==="
rm -rf "$ARTIFACTS_DIR"
meson install -C "$BUILD_DIR" --destdir "$ARTIFACTS_DIR"

# Achar o prefixo real dentro do destdir (varia com --prefix do meson, default /usr/local)
INSTALL_ROOT="$(find "$ARTIFACTS_DIR" -maxdepth 2 -iname lib -type d | head -1 | xargs dirname)"

echo ""
echo "=== Resumo do build ==="
echo "Mesa $MESA_VERSION, patch PS4 Gladius/Liverpool aplicado."
find "$INSTALL_ROOT" \( -iname "radeonsi_dri.so" -o -iname "libvulkan_radeon.so" -o -iname "libGLX_mesa.so*" -o -iname "libEGL_mesa.so*" -o -iname "libgbm.so*" \) -exec ls -lh {} \;

# Tarball final pronto pra copiar/testar no PS4 via LD_LIBRARY_PATH, e um
# "latest" estavel (copia, nao symlink -- symlink quebraria se alguem mover a
# pasta mesa/ inteira) para o pipeline de imagem (01-build-image-7.0.sh)
# consumir sem precisar saber a versao exata compilada.
TARBALL_OUT="$SCRIPT_DIR/mesa-$MESA_VERSION-ps4-gladius-liverpool.tar.xz"
TARBALL_LATEST="$SCRIPT_DIR/mesa-ps4-gladius-liverpool-latest.tar.xz"
tar -cJf "$TARBALL_OUT" -C "$INSTALL_ROOT" .
cp -f "$TARBALL_OUT" "$TARBALL_LATEST"
echo ""
echo "=== Build concluido ==="
echo "Artefatos: $INSTALL_ROOT"
echo "Pacote:    $TARBALL_OUT"
echo "Latest:    $TARBALL_LATEST  (consumido automaticamente por 01-build-image-7.0.sh)"
echo ""
echo "Para testar manualmente no PS4 (sem sobrescrever o Mesa do sistema):"
echo "  scp \"$TARBALL_OUT\" root@<ip-ps4>:/opt/"
echo "  ssh root@<ip-ps4> 'mkdir -p /opt/mesa-ps4-patched && tar xJf /opt/$(basename "$TARBALL_OUT") -C /opt/mesa-ps4-patched'"
echo "  # depois, como o usuario da sessao grafica:"
echo "  export LIBGL_DRIVERS_PATH=/opt/mesa-ps4-patched/lib/dri"
echo "  export LD_LIBRARY_PATH=/opt/mesa-ps4-patched/lib:\$LD_LIBRARY_PATH"
echo "  glxinfo | grep renderer   # deve mostrar 'gladius', nao 'kaveri'"
echo ""
echo "Este pacote 'latest' ja e incorporado automaticamente pelo pipeline de"
echo "imagem (distros/arch_minimal_v2/01-build-image-7.0.sh), que extrai ele"
echo "para /opt/mesa-ps4-patched dentro do rootfs e persiste as variaveis de"
echo "ambiente via /etc/environment -- nao precisa fazer deploy manual pra"
echo "isso valer na proxima imagem gravada."
