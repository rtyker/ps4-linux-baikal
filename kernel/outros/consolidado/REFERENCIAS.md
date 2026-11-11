# Referências e Links

## Canais e Comunidades

| Recurso | URL |
|---------|-----|
| Canal PS4 Linux (YouTube) | https://www.youtube.com/@ps4linux |
| PS4 Linux Site Oficial | https://ps4linux.com/ |
| PS4 Linux Fórum | https://ps4linux.com/forums/ |
| PS4 Linux Downloads | https://ps4linux.com/downloads/ |
| PS4 Linux AIO Documentation | https://ps4linux.com/ps4-linux-documentation-aio/ |
| PS4 Linux Kernel FAQ | https://ps4linux.com/ps4-linux-kernel-faq/ |
| PS4 Linux sem instalar | https://ps4linux.com/run-ps4-linux-without-installing/ |
| PS4 Baikal/Belize MT7768 VPN | https://ps4linux.com/ps4-baikal-belize-mt7768-vpn-opensource/ |
| PS4 Pro Vulkan Fix | https://ps4linux.com/ps4-pro-fix-vulkan-fix-crash/ |
| SteamOS 3 para PS4 | https://ps4linux.com/steamos-3-ps4-nazky/ |

## Repositórios GitHub

| Repositório | Descrição |
|-------------|-----------|
| https://github.com/ps4-linux/ps4-linux-loader | **Payload kexec v24b.1** - firmware agnóstico, detecção runtime |
| https://github.com/rmuxnet/linux | **Kernel Strawberry 7.0.8** - Baikal branch: `baikal/7.0.8-Stable` |
| https://github.com/feeRnt/ps4-linux-12xx | Kernel PS4 12xx (Baikal 5.4.247-neocine, Belize 5.15/6.15) |
| https://github.com/DFAUS-git/ps4-baikal-5.4.247-kernel | Kernel Baikal 5.4.247 original |
| https://github.com/noob404yt/baikal-5.4.213-mt7668-dns-vpn | Kernel Baikal com MT7668 + Wireguard |
| https://github.com/noob404yt/ps4-custom-mesa-archlinux | Mesa customizado para PS4 |
| https://github.com/centi07/arch-ps4-aur | Arch PS4 AUR packages |
| https://github.com/whitehax0r/ArchLinux-PS4 | ArchLinux PS4 |
| https://github.com/Hakkuraifu/PS4Linux-ArchDrivers | Drivers Arch para PS4 |
| https://github.com/HoppersPS4/Waste_Ur_Time | Passcode finder |
| https://github.com/hippie68/psxitarch-how-to | Tutorial Psxitarch |

## Tutoriais

| Tutorial | URL |
|----------|-----|
| Tutorial Warfare PS4 Linux | https://www.youtube.com/watch?v=qlsdUcYrV2M |
| PS4 Linux Tutorial (dionkill) | https://dionkill.github.io/ps4-linux-tutorial/ |
| Tutorial Instalação interna HDD | https://dionkill.github.io/ps4-linux-tutorial/internal-installation.html |
| HDD Mounting/Decryption on Linux | https://www.psx-place.com/threads/tutorial-hdd-mounting-and-decryption-on-linux.42314/ |
| Extrair chaves do HDD | https://www.youtube.com/watch?v=xcPEjxGHoE4 |
| Batocera 40 Tutorial | https://ps4linux.com/forums/d/252-batocera-40-for-ps4-installation-setup-tutorial |
| Fedora 38 by DF_AUS | https://ps4linux.com/forums/d/117-fedora-38-by-df-aus |
| Arch Linux Minimal | https://ps4linux.com/forums/d/413-archlinux-minimal |

## Payloads e Exploits

| Recurso | URL |
|---------|-----|
| PSFree-Enhanced Host | https://arabpixel.github.io/PSFree-Enhanced |
| GoldHEN | Incluído nas utilities do projeto |
| Payload loader repo | https://github.com/ps4-linux/ps4-linux-loader |
| Payload sender (nc) | `nc -w 3 <IP> 9090 < linux-3072mb.elf` |

## Links para Download

| Site | URL | Tipo |
|------|-----|------|
| AkiraBox | https://akirabox.to | Jogos PKG |
| DLPSGame | https://dlpsgame.com/category/ps4/ | Jogos PKG |
| SuperPSX | https://www.superpsx.com | Jogos PKG |
| Archive.org PS4 ROMs | https://archive.org/download/PS4_ROMSFUN_COM/ | Roms |
| Archive.org PS4 FPKG | https://archive.org/details/ps4-fpkg-collection-english-f | FPKG Collection |
| Orbis Patches | https://orbispatches.com/ | Patches de jogos |
| PSX Patches | https://psxpatches.com/ | Patches alternativos |
| PSDevWiki PS2 Classics | https://www.psdevwiki.com/ps4/PS2_Classics_Emulator_Compatibility_List | Compatibilidade PS2 |
| PSXPlace | https://www.psx-place.com | Fórum homebrew |
| PSXHax | https://www.psxhax.com | Utilitários |
| ES7IN1 | http://es7in1.site | Site de exploits |

## Ferramentas

| Ferramenta | Descrição |
|------------|-----------|
| Chiaki | Remote Play para Linux (`wget https://git.sr.ht/~thestr4ng3r/chiaki/refs/download/v2.1.1/Chiaki-v2.1.1-Linux-x86_64.AppImage`) |
| GoldHEN | Exploit e payload loader |
| PS4 Remote PKG Sender | Envia PKGs para o PS4 remotamente |
| PS4-Fake-PKG-Tools | Ferramentas de criação de PKG |
| ps4-pkg-tools | Ferramentas PKG em C++ |
| pkg_pfs_tool | Ferramenta de manipulação PFS |
| PS4PKGViewer | Visualizador de arquivos PKG |

## Monitor e Bootargs (Testes)

| Recurso | Caminho | Descrição |
|---------|---------|-----------|
| **Pasta monitor_edid** | `../monitor_edid/` | **Guia principal de monitor e testes de bootargs.** Contém EDID binário, log de tentativas, info do monitor LG e patch do bridge DP→HDMI para 1080p. |
| TENTATIVAS_LOG.md | `../monitor_edid/TENTATIVAS_LOG.md` | Histórico de todos os testes realizados com bootargs no monitor |
| MONITOR_INFO.md | `../monitor_edid/MONITOR_INFO.md` | Análise completa do monitor LG Full HD (EDID, timings, compatibilidade com PS4 bridge) |
| edid.bin | `../monitor_edid/edid.bin` | EDID bruto capturado do monitor (256 bytes) |
| Patch bridge 1080p | `../monitor_edid/ps4_bridge_1080p_monitor.patch` | Patch para ps4_bridge.c forçando 1080p em monitores |

## Documentação Arch Linux

| Recurso | URL |
|---------|-----|
| Arch Linux Wiki | https://wiki.archlinux.org/ |
| Chaotic-AUR | https://aur.chaotic.cx/ |
| Arch Linux PS4 AUR | https://github.com/centi07/arch-ps4-aur |
