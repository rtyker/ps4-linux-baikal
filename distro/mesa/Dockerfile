# Mesa PS4 Gladius/Liverpool Build Container
# 
# Uso:
#   docker build -t mesa-ps4-build .
#   docker run --rm -v "$(pwd):/repo" -v "/mnt/hdauxiliar/temp:/mnt/hdauxiliar/temp" mesa-ps4-build
#
# O script de build (01-build-mesa.sh) é executado como entrypoint.
# Artefatos saem em distro/mesa/build_artifacts/ e distro/mesa/mesa-*-ps4-gladius-liverpool.tar.xz

FROM archlinux:latest

# Metadados
LABEL maintainer="PS4 Linux Baikal Project"
LABEL description="Build environment for Mesa with PS4 Gladius/Liverpool patches"

# Instalar dependências de build (cache layer)
RUN pacman -Sy --noconfirm --needed \
    base-devel \
    meson \
    ninja \
    git \
    pkgconf \
    python \
    python-mako \
    python-setuptools \
    python-yaml \
    llvm \
    clang \
    libdrm \
    wayland \
    libglvnd \
    libunwind \
    libxml2 \
    libxkbcommon \
    libxrandr \
    libva \
    glslang \
    && pacman -Sc --noconfirm

# Diretório de trabalho
WORKDIR /repo

# Copiar apenas o necessário para o build (cache-friendly)
COPY distro/mesa/01-build-mesa.sh distro/mesa/
COPY distro/mesa/ps4-gladius-liverpool-patch/ distro/mesa/ps4-gladius-liverpool-patch/

# Entry point: roda o script de build
ENTRYPOINT ["/repo/distro/mesa/01-build-mesa.sh"]

# Default: versão compatível com host (pacman -Q mesa)
CMD []