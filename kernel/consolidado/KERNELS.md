# Documentação dos Kernels para PS4

## Kernels Disponíveis no Projeto

| Versão | Diretório | Observações |
|--------|-----------|-------------|
| 5.4.247 (DFAUS) | kernels/5.4.247/ | Último 5.4 LTS - **KERNEL ATUALMENTE USADO** |
| 5.4.247-neocine | kernels/5.4.247-neocine/ | Versão modificada para Baikal (feeRnt) |
| 7.0.8 (Strawberry) | kernels/strawberry-7.0/ | Kernel 7.0.8 para Baikal (rmuxnet) |

## Kernel da Distro Consolidada

- **Versão**: 6.12.57-1-lts
- **Arquitetura**: x86_64
- **Tipo**: LTS (Long Term Support)
- **Localização**: `/consolidado/rootfs/usr/lib/modules/6.12.57-1-lts/`

## Kernels Recomendados para Baikal

### Kernel 7.0.8 (Strawberry) - RECOMENDADO (Abr 2026)

Pela primeira vez, Baikal foi portado para kernel 7.0. Desenvolvido por **rmuxnet**:

```bash
git clone https://github.com/rmuxnet/linux --branch baikal/7.0.8-Stable --depth=3
cd linux
./build.sh --option 3 use=General lto=ThinLTO
# Saída: out/bzImage
```

**Features**:
- Kernel 7.0.8 estável para Baikal (Slim e Pro)
- UART, USB, display funcionais
- WiFi/BT MediaTek 7668
- Perfis: General (desktop/gaming) ou Server (headless)
- ThinLTO / FullLTO
- GitHub Actions geram bzImage pré-compilado

### Kernel 5.4.247-neocine-1.1 (feeRnt - Mar 2026)

Última versão do kernel 5.4 LTS para Baikal, do repositório `feeRnt/ps4-linux-12xx`:

| Feature | Detalhe |
|---------|---------|
| Base | DFAUS-git/ps4-baikal-5.4.247-kernel |
| WiFi/BT | MediaTek 7668 Driver (mt76x8; MT6632 variant) |
| Tela preta | Fix no login e initramfs (WIP) |
| GPU | Fixed AMDGPU Gladius Registers (melhora performance no Pro) |
| Compressão | ZRAM, ZSWAP, ZBUD |
| Otimizações | march=btver2, mtune=btver2, -O3 |
| Compilador | Clang/LLVM-14 ou GCC-11 |

**⚠️ Atenção**: Kernel 5.4 NÃO suporta libdrm novo. Use Mesa ≤ 25.1 ou perderá aceleração 3D.

### Outros kernels Baikal

Source adicionais:
- https://github.com/DFAUS-git/ps4-baikal-5.4.247-kernel
- https://github.com/noob404yt/baikal-5.4.213-mt7668-dns-vpn (com MT7668 + DNS fix + Wireguard)
- https://github.com/whitehax0r/ps4-linux-baikal (5.4.213 original)

O kernel baikal inclui drivers específicos para:
- Southbridge Baikal
- WiFi/Bluetooth MT76 (MediaTek)
- Suporte a HDMI
- Drivers de áudio

## Parâmetros de Boot do Kernel

Os parâmetros são configurados no arquivo `bootargs.txt` na partição FAT32 de boot.

### Parâmetros Otimizados para PS4 Baikal

```text
video=HDMI-A-1:1920x1080@60e panic=0 clocksource=tsc consoleblank=0
net.ifnames=0 radeon.dpm=0 amdgpu.dpm=0 drm.debug=0
console=uart8250,mmio32,0xC890E000 console=ttyS0,115200n8 console=tty0
drm.edid_firmware=edid/1920x1080.bin
```

### Explicação dos Parâmetros

| Parâmetro | Função |
|-----------|--------|
| `video=HDMI-A-1:1920x1080@60e` | Força resolução 1080p@60Hz na saída HDMI |
| `drm.edid_firmware=edid/1920x1080.bin` | Injeta EDID falso para monitores |
| `radeon.dpm=0` | Desativa gerenciamento dinâmico de energia (GPU) - evita travamentos |
| `amdgpu.dpm=0` | Desativa DPM da AMDGPU - evita travamentos |
| `clocksource=tsc` | Usa Time Stamp Counter como clock - mais estável |
| `console=uart8250,mmio32,0xC890E000` | UART para Baikal |
| `consoleblank=0` | Desativa blank da tela (PS4 não acorda) |
| `net.ifnames=0` | Nomes de rede previsíveis (eth0, wlan0) |
| `panic=0` | Comportamento em kernel panic |
| `drm.debug=0` | Verbosidade de debug de vídeo reduzida |

## Configuração do Initramfs

O initramfs é configurado via `/etc/mkinitcpio.conf`:

```conf
HOOKS=(base systemd autodetect microcode modconf kms keyboard keymap
       sd-vconsole block filesystems fsck)
```

## bzImage

O arquivo `bzImage` (kernel comprimido) é o kernel do Linux compilado.
Tamanho aproximado: 7-8MB.
Localização no projeto: `distros/bzImage` e `kernels/bzImage`.

## Compilação do Kernel

### Kernel 5.4 (tradicional)
```bash
git clone https://github.com/DFAUS-git/ps4-baikal-5.4.247-kernel
cd ps4-baikal-5.4.247-kernel
mv config .config
make -j$(nproc) bzImage
# Saída: arch/x86/boot/bzImage
```

### Kernel 7.0 (Strawberry - rmuxnet)
```bash
git clone https://github.com/rmuxnet/linux --branch baikal/7.0.8-Stable --depth=3
cd linux
./build.sh --option 3 use=General lto=ThinLTO
# Saída: out/bzImage
```

### Kernel feeRnt (5.4.247-neocine)

O código-fonte deste kernel já está clonado localmente para compilação em:
* Diretório local: `/mnt/hdauxiliar/temp/kernel_build`

Para clonar manualmente a partir do repositório remoto:
```bash
git clone https://github.com/feeRnt/ps4-linux-12xx --branch v5.4.247__neocine-1.1
cd ps4-linux-12xx
# Compilar com GCC-11 ou LLVM-14 (ou use o script 00-build-kernel.sh no projeto)
make -j$(nproc) bzImage
```

Após compilar, gere o initramfs com `mkinitcpio`.
