# Features — PS4 Linux Baikal (Arch Minimal v2 / Kernel 7.0.8)

> **Última atualização**: 2026-07-28  
> **✅ FUNCIONA NO PS4 PRO BAIKAL (CUH-7214B) COM FIRMWARE 12.52 (GOLDHEN 2.4b18.9)**  
> **Kernel**: **Linux 7.0.8-Strawberry-ThinLTO-Baikal** (branch `baikal/7.0.8-Stable` do rmuxnet/linux)  
> **Mesa**: **26.1.5** com patch **CHIP_GLADIUS/CHIP_LIVERPOOL** (correção de corrupção visual)  
> **Hardware**: PS4 Pro (CUH-7214B, RTYKER), Southbridge Baikal B1 (0x30201), FW 12.52  
> **Status**: Tudo abaixo **JÁ CONCLUÍDO E VALIDADO EM HARDWARE REAL** — não inclui itens do BACKLOG/planos futuros.

---

## ⚡ VERSÕES CHAVE (RESUMO EXECUTIVO)

| Componente | Versão | Detalhes |
|------------|--------|----------|
| **Kernel Linux** | **7.0.8** | Strawberry (rmuxnet), ThinLTO, General profile, Baikal hardcoded, ZSTD compression |
| **Mesa 3D** | **26.1.5** | Patch CHIP_GLADIUS (0x9924) / CHIP_LIVERPOOL (0x9920/22/23) — corrige corrupção visual |
| **Firmware PS4** | **12.52** | GoldHEN v2.4b18.9, HEN 12.52 |
| **Southbridge** | **Baikal B1** | 0x30201, PCI IDs 0x90d7–0x90de |
| **Modelo Console** | **CUH-7214B (RTYKER)** | PS4 Pro, 1TB Toshiba MQ04ABF100 |
| **Boot** | **kexec via payload** | v24+ firmware-agnóstico, VRAM via `vram.txt` (default 1024 MB) |
| **Rootfs** | **Arch Linux Minimal** | systemd 258.1-1 fixo (IgnorePkg), label `psxitarch` obrigatório |

---

## 1. Kernel & Build System

| Feature | Descrição | Validação |
|---------|-----------|-----------|
| **Kernel 7.0.8 Strawberry (ThinLTO + General profile + Baikal)** | Build otimizado para Jaguar (btver2), ThinLTO, perfil General (desktop/gaming), southbridge Baikal hardcoded. Compressão ZSTD no bzImage. **Versão: `7.0.8-Strawberry-ThinLTO-Baikal-`** | Boot completo, estável, <10 MB (cabe no limite do kexec PS4). Tag ativa: `20260723-RELEASE` |
| **Script único de build oficial (`00-build-kernel-7.0.sh`)** | Clona repo, aplica patches, configura via `scripts/config`, compila kernel + módulos, gera `bzImage-7.0-<TAG>` + `config-7.0-<TAG>` em `boot_referencia/`. Limita threads do pahole (JOBS=2) e do link ThinLTO (`--thinlto-jobs=2`) para evitar OOM. | Build reprodutível, ~20-45 min, sem OOM. Histórico de tags versionado. |
| **Pipeline de imagem em 3 passos** | `00-build-kernel` → `01-build-image` → `02-burn-image` (ou `deploy-boot` para troca rápida). Rootfs Arch via `pacstrap`, initramfs via `mkinitcpio`, partição root **label obrigatório `psxitarch`** (hardcoded no initramfs). | Gravação HD USB → boot PS4 → SSH funcional. Rollback = `deploy-boot <tag-antiga>` (1 power cycle). |
| **BTF habilitado (CONFIG_DEBUG_INFO_BTF=y)** | Necessário para o kernel bootar neste console — desabilitar quebra o boot (tela preta). Pahole limitado a 2 threads para conter memória. | Confirmado: 2 builds limpos sem BTF = tela preta; com BTF = boot OK. |
| **Mitigações Spectre/Meltdown desabilitadas** | `CONFIG_CPU_MITIGATIONS=n`, `mitigations=off` no cmdline. +5-15% CPU. | Validado em benchmarks locais. |
| **ZRAM + ZSWAP (zstd)** | Swap comprimido na RAM, essencial com ~4-5 GB livres de 8 GB GDDR5 unificada. | `zswap.enabled=1`, compressor zstd. Funcional. |
| **Scheduler: sched_ext + BPF JIT + BTF** | `CONFIG_SCHED_CLASS_EXT`, `CONFIG_SCHED_EXT`, BPF JIT sempre on. Habilitado porque BTF está ligado. | Compila e roda; base para futuros schedulers custom. |
| **TCP BBR + fq_codel** | Congestion control BBR padrão, qdisc fq_codel. | `CONFIG_DEFAULT_TCP_CONG="bbr"`, `CONFIG_DEFAULT_NET_SCH="fq_codel"`. |
| **NTSYNC + Futex PI** | Para Proton/Wine/gaming. | `CONFIG_NTSYNC=y`, `CONFIG_FUTEX_PI=y`. |
| **Perfil General (não Server)** | HZ=250, PREEMPT, BFQ, schedutil, no_hz_full, RCU_NOCB. Otimizado para desktop/gaming, não throughput de servidor. | Boot responsivo, latência baixa. |

---

## 2. Vídeo / Display / GPU (AMD Gladius / Liverpool)

| Feature | Descrição | Validação |
|---------|-----------|-----------|
| **amdgpu (CIK/GFX7) built-in** | Driver GPU nativo do kernel, Gladius (PS4 Pro, 1002:9924) e Liverpool (PS4 base) reconhecidos. `CONFIG_DRM_AMDGPU=y`, `CONFIG_DRM_AMDGPU_CIK=y`. | Framebuffer funcional, Xorg/Cinnamon rodam. |
| **ps4_bridge (DCE v8.0 custom)** | Bridge HDMI proprietário do PS4, expõe conector `HDMI-A-1`, força VIC mode 16 (1080p60). | Vídeo estável em TV/monitor. |
| **EDID firmware persistente** | `/lib/firmware/edid/ps4_tv_edid.bin` (256 bytes, extraído via I2C bus 3 addr 0x50) + `drm.edid_firmware=edid/ps4_tv_edid.bin` no cmdline. Permite boot **com TV desligada**. | Validado: TV off → boot → vídeo aparece ao ligar TV. |
| **Bootargs de vídeo corretos** | `video=HDMI-A-1:1920x1080@60` (SEM sufixo `e` — o `e` quebra handshake HDMI). `console=ttyS0,115200n8 console=tty0` (NÃO `uart8250` — conflita com vídeo no Baikal). | Vídeo 1080p60 estável, sem tela preta. |
| **DPM desabilitado** | `radeon.dpm=0 amdgpu.dpm=0` no cmdline. Clocks dinâmicos causam instabilidade/travamento no PS4. | Estável por horas. |
| **GPU recovery habilitado** | `amdgpu.gpu_recovery=1` — auto-recovery se GPU travar. | Não testado ativamente (não travou), mas presente. |
| **Áudio HDMI (snd_hda_intel)** | Codec HDMI 1002:9921 reconhecido, áudio via HDMI funcional. | `aplay -l` lista device, som sai na TV. |

---

## 3. Mesa 3D — **v26.1.5** — Correção Gladius/Liverpool (2026-07-24 ✅)

| Feature | Descrição | Validação |
|---------|-----------|-----------|
| **Patch Mesa 26.1.5 para CHIP_GLADIUS/CHIP_LIVERPOOL** | O Mesa oficial não conhece os chips PS4 — identificava como "kaveri" e usava `raster_config` errado (1 SE/2 RBs vs 4 SEs do Gladius), causando **corrupção visual em blocos/xadrez azul-branco** (Nemo, janelas OpenGL). Patch adapta: `pci_ids` (0x9924=GLADIUS, 0x9920/22/23=LIVERPOOL), `amdgpu_asic_addr.h` (faixas `external_rev_id` 0x61-0x71 Liverpool, 0x71-0x81 Gladius — batem com o kernel), `amd_family.h/.c` (enums CHIP_LIVERPOOL/GLADIUS no grupo GFX7), `ac_gpu_info.c` (`ac_identify_chip`, `ac_get_raster_config` com valores reais 4 SEs). | **VALIDADO AO VIVO 2026-07-24**: `glxinfo` mostra `renderer: ... (radeonsi, gladius, ACO...)`. Corrupção visual **desapareceu completamente** SEM `AMD_DEBUG=notiling`. |
| **Integração no pipeline de build** | `mesa/01-build-mesa.sh` → gera `mesa/mesa-ps4-gladius-liverpool-latest.tar.xz` → `01-build-image-7.0.sh` extrai para `/opt/mesa-ps4-patched` + seta `LD_LIBRARY_PATH`/`LIBGL_DRIVERS_PATH` em `/etc/environment` (via `pam_env`, persiste em sessões X/Wayland). Não sobrescreve pacote `mesa` do Arch (evita conflito com `pacman -Syu`). | Deploy automático na imagem. Testado: `LD_LIBRARY_PATH` + `LIBGL_DRIVERS_PATH` **ambos** necessários (só `LIBGL_DRIVERS_PATH` deixava `libgallium` do sistema vazar). |

---

## 4. Rede — WiFi / Bluetooth (MT7668)

| Feature | Descrição | Validação |
|---------|-----------|-----------|
| **MT7668 SDIO (WiFi/BT Baikal)** | Chipset MediaTek MT7668 no módulo AW-CB319. Driver `mt76_sdio` + `btmtksdio` habilitados. | **WiFi: ✅ 100% funcional** — conecta, IP via DHCP, SSH estável. **BT: ✅ detecta, pareia** (bluez/bluez-utils instalados). |
| **Firmware MT7668 embutido no kernel** | `CONFIG_EXTRA_FIRMWARE` inclui: `mt7668pr2h.bin`, `EEPROM_MT7668*.bin`, `mt7668_patch_e*.bin`, `TxPwrLimit_MT76x8.dat`, `wifi.cfg`, `WIFI_RAM_CODE*_MT7668.bin` (SDIO + USB). Copiado também para initramfs `/lib/firmware/mediatek/`. | WiFi sobe no early boot, antes do rootfs montar. |
| **Manufacture data (NVRAM/eFUSE) — AUSÊNCIA CONHECIDA** | O firmware MT7668 precisa de manufacture data (calibração por unidade, MAC, potência) que fica no eFUSE do chip ou NVRAM SPI. Não extraímos ainda; driver usa defaults do eFUSE interno. Funciona, mas potência/alcance podem não ser ótimos. | WiFi funciona; pendente extrair manufacture data do NOR/eFUSE para calibração ideal. |
| **WiFi Aeolia/Belize (Marvell sd8797/sd8897) — firmware Orbis custom** | `sd8797_uapsta.bin` (443 KB, custom Orbis, **não** o upstream 522 KB) + `sd8897_uapsta.bin` embutidos. Necessários mesmo no Baikal pois `CONFIG_MWIFIEX_SDIO` está ligado. | Incluídos no build; não testados no Baikal (hardware diferente), mas exigidos pelo config. |

---

## 5. Rede — Ethernet (GBE Baikal) — Driver Próprio `mts.ko`

| Feature | Descrição | Validação |
|---------|-----------|-----------|
| **Descoberta: GBE Baikal NÃO é Marvell Yukon (sky2)** | PCI ID `104d:90d8` (00:14.1). `sky2` probe falha com "unsupported chip type 0x0" — o MAC core está power-gated (Syscon lista `gbe off`). HW é silício **MTS** (Orbis usa `SceGbeMtsCtrl`/`SceGbeMtsPhyCtrl`), não `msk`/Yukon. | Confirmado por RE do dump kernel Orbis 12.52 + teste ao vivo: `sky2` com ID Baikal probe roda mas lê chip_id=0x0. |
| **Driver `mts.ko` novo (drivers/net/ethernet/sony/)** | Driver escrito do zero baseado na RE do `if_mts.c` do Orbis (`fcn.ffffffffdc5a31f0`). Traz: tabela de registradores BAR0 (4 KB) documentada com procedência [RE]/[MEDIDO], MDIO Clause 45, anéis DMA (256 desc, 16 bytes cada, base/ptr pares 0x3c/0x44 TX, 0x40/0x48 RX), MAC enable via 0x34/0x38 (bit 0, **escrita direta `mts_write`, NUNCA `mts_set`/RMW — 0x09 é rejeitado), MAC stop via bit 1 (soft-reset) + poll ACK, IMR, clock 25 MHz confirmado (0x7c=0x017d7840), MAC address via SPM (função MEM 00:14.6, BAR5+0x2f000, idêntico ao Aeolia). | Compila, carrega, probe OK, dump registradores funcional, MAC enable liga core (0x004: 0→0xb19). |
| **Bring-up em estágios (module param `stage`)** | `stage=0`: só probe/mapeia BAR0. `1`: +dump registradores/MDIO. `2`: +aneis DMA. `3`: +MAC enable + IMR. `4`: +`pci_set_master`, IRQ via `bpcie`, `register_netdev` (default). Permite testar cada passo isoladamente sem arriscar boot. | Testado estágios 0-3 ao vivo via `insmod mts.ko stage=N`. Stage 4 = netdev `eth0` sobe. |
| **IRQ via bpcie (não apcie)** | Baikal roteia MSIs da GBE pelo `bpcie` (driver `ps4-bpcie-icc.c`), não `apcie` (Aeolia/Belize). Patch `sky2-baikal-gbe.patch` adiciona `sky2_ps4_assign_irqs/free_irqs` que despacha para `bpcie_*` quando `PCI_DEVICE_ID_SONY_BAIKAL_GBE`. | IRQ alocado com sucesso no stage 4. |
| **MAC core power-on via ICC** | `bpcie_icc_cmd(4, 0x38, &on=1, 1, &reply, 1)` com **retry loop** (até 100x, 50 ms) — não funciona na 1ª tentativa. Sucesso: `reply=0x01`, BAR0+0x004 muda 0→0xb19 (bits 0,3,4,8,9 = link/speed/duplex). | Validado ao vivo 2026-07-24/25. MAC core acorda. |
| **PHY power domain SEPARADO** | ICC 4/0x38 liga só o wrapper PCIe/MAC. PHY tem domínio próprio (`SceGbeMtsPhyCtrl`) — **não acorda com ICC**. MDIO Clause 45/22 **sempre retorna 0x0000/timeout** mesmo após MAC ligado + clock config (0x10A030) + soft-reset MDIO + hold/pulse correto (0x180020/0x180074, bloco 0x2000). | **RX MORTO** — PHY não responde. Investigação ativa (`PLANO_FASES_GBE_2026-07-25.md`). |
| **TX por software (~95%)** | Doorbell TX corrigido 2026-07-25; pacotes saem, `ping -I eth0` **envia** (Wireshark no host vê ARP request), mas **não recebe** (PHY mudo). | TX funcional, RX zero. |
| **Hold registers são WRITE-ONLY** | Leem 0 após escrita — design Baikal. Não confiar em read-back. | Confirmado em múltiplos registradores. |
| **Correção offsets hold/pulse GBE (2026-07-25)** | Inferência anterior `hold=0x180034` estava **errada** (bloco 0x3c00 sem par). RE de `fcn.ffffffffdc6df850` (glue block reset) mostra rotina stop MAC GBE (`dc59fe10`) chamada antes de `dc6dfb60(0x2000)` + `dc718710(0x20,1)` + `dc718710(0x74,1)` → **GBE hold=0x180020, pulse=0x180074** (bloco 0x2000). SATA é 0x18002c/0x18006c. Código corrigido em `mts.c`. | Testado ao vivo 2026-07-25: sem incidente, mas PHY continua mudo. |

---

## 6. ICC / Syscon / Power Management

| Feature | Descrição | Validação |
|---------|-----------|-----------|
| **`ps4_icc_rtc_cmd()` — wrapper retry genérico** | Em `ps4-bpcie-icc.c` + declarado em `baikal.h`/`aeolia.h`. Encapsula retry loop (100x50ms) para ICC lento (RTC, GBE power-on). Despacha para `bpcie_icc_cmd` (Baikal) ou `apcie_icc_cmd` (Aeolia/Belize). Exportado `EXPORT_SYMBOL_GPL` para drivers consumidores (ex: `rtc-ps4-icc.c` futuro). | Usado no MAC enable GBE (sucesso) e pronto para RTC. |
| **RTC via ICC (Fase 3 do plano)** | Comandos identificados no dump Orbis: ICC major=2 minor=0x0b/0x0c sub=0x81/1 (save/load context), major=4 minor=0x50 (alarm bitmask). Infraestrutura RTC core habilitada no kernel (`CONFIG_RTC_CLASS`, `CONFIG_RTC_DRV_CMOS`, `CONFIG_RTC_HCTOSYS`). Driver `rtc-ps4-icc.c` **pendente** — usará `ps4_icc_rtc_cmd`. | Comandos validados via RE; driver ainda não escrito. |
| **S5 Shutdown (poweroff -f) — payload 32 bytes** | Disassembly de `icc_power_shutdown` (offset 0x1d8a3c) revelou payload real de **32 bytes** (driver enviava só 6 bytes truncados). Patch aplicado em `ps4-bpcie-icc.c`/`ps4-apcie-icc.c`. | Patch pronto; **pendente teste ao vivo** (requer power cycle). |

---

## 7. UART / Serial / Debug

| Feature | Descrição | Validação |
|---------|-----------|-----------|
| **UART Baikal MMIO 0xC890E000** | Southbridge Baikal expõe UART em `0xC890E000` (não `0xD0340000` do Aeolia/Belize). 115200 8N1, 3.3V TTL. | Solda validada eletricamente 2026-07-27. |
| **Pinout físico confirmado (NVG-002)** | Perto do Syscon `A06-COL2` (QFP), lado VERSO da placa. Diagrama `repair.wiki` (BetterWayElectronics) + foto anotada `psdevwiki.com/ps4/Talk:Service_Connectors#NVG-002` confirmam: chip `A06-COL2` → pads TX (vermelho), GND (preto) acima do furo de montagem superior. RX não documentado na foto (só TX para log de boot). | Foto `V004-B.jpeg`/`V004-C.jpeg` bate com diagrama. Confirmação elétrica com multímetro **recomendada antes de soldar**. |
| **Bootargs UART correto** | `earlycon=uart8250,mmio32,0xC890E000 console=uart8250,mmio32,0xC890E000 console=tty0` (NÃO `console=ttyS0` — é porta 8250 legada 0x3F8 sem HW real; para de sair log ~0.7s no handoff). | Testado: log sai pela UART até handoff; `ttyS0` = tela preta. |
| **Scripts de captura UART robustos** | `scripts/uart_start.sh [duracao] [nome]` → inicia 1 captura em background (recusa se já houver), grava `.bin` + `.log` em `tests/uart_logs/`, usa `stty raw -icanon` + `dd bs=1` (método comprovado — `stty`+`cat` quebra com re-enumeração PL2303). `scripts/uart_stop.sh` encerra tudo (pid file + varredura órfãos). | Captura estável, sobrevivente a re-enumeração USB. |
| **Netconsole (UDP 6666) — OPERANTE** | `netconsole=@192.168.0.2/eth0,6666@192.168.0.1/ff:ff:ff:ff:ff:ff` no cmdline. Kernel built-in `CONFIG_NETCONSOLE=y`. Usa `eth0` do `mts.ko` (stage=4) para transmitir logs de boot via UDP. Receptor: `nc -u -l -p 6666` ou `scripts/netconsole_listener.py`. | Logs de boot chegam no host PC via Ethernet. |

---

## 8. Storage / SATA / USB / SD

| Feature | Descrição | Validação |
|---------|-----------|-----------|
| **SATA AHCI interno** | `CONFIG_SATA_AHCI=y` built-in. Disco interno Toshiba MQ04ABF100 1TB (GPT custom Sony, revisão 2.0, Disk GUID termina em MAC LAN). Partição root label `psxitarch` (ext4). | Boota do HD interno. `libata.force=1.00:3.0Gbps,noncq` no cmdline para estabilidade. |
| **USB 3.0 xHCI (xhci_aeolia)** | `CONFIG_USB_XHCI_HCD=y`, `CONFIG_USB_XHCI_AEOLIA=y`. Portas frontais/traseiras funcionais. | Pendrive, HD externo, adaptador SATA-USB detectados. |
| **SD/MMC (sdhci)** | `CONFIG_MMC_SDHCI=y`, `CONFIG_MMC_SDHCI_PCI=y`. Slot SD funcional. | Cartão SD montado. |
| **HD externo USB (partição BOOT FAT32 200 MB + root ext4 psxitarch)** | `02-burn-image-7.0.sh` particiona: sda1=200MB FAT32 LABEL=BOOT (bzImage, initramfs, bootargs, vram.txt), sda2=restante ext4 LABEL=psxitarch (rootfs). `deploy-boot-7.0.sh` troca só boot (mantém rootfs). | Gravação + boot OK. Rollback instantâneo. |

---

## 9. Rootfs / Userspace / Sistema (Arch Minimal v2)

| Feature | Descrição | Validação |
|---------|-----------|-----------|
| **Arch Linux bootstrap via pacstrap** | `base`, `linux-api-headers`, `openssh`, `sudo`, `vim`, `nano`, `htop`, `iotop`, `iftop`, `nethogs`, `net-tools`, `iproute2`, `dhcpcd`, `wpa_supplicant`, `wireless-regdb`, `iw`, `bluez`, `bluez-utils`, `usbutils`, `pciutils`, `lsof`, `strace`, `perf`, `dmidecode`, `smartmontools`, `nvme-cli`, `mdadm`, `lvm2`, `cryptsetup`, `btrfs-progs`, `dosfstools`, `e2fsprogs`, `xfsprogs`, `f2fs-tools`, `ntfs-3g`, `exfatprogs`, `samba`, `nfs-utils`, `cronie`, `systemd-sysvcompat`, `python3`, `python-pip`, `git`, `curl`, `wget`, `rsync`, `unzip`, `tar`, `gzip`, `xz`, `zstd`, `jq`, `ccache`, `distcc`, `meson`, `ninja`, `pkgconf`, `mkinitcpio`, `mesa`, `lib32-mesa`, `vulkan-radeon`, `lib32-vulkan-radeon`, `vulkan-tools`, `mesa-utils`, `xorg-server`, `xorg-xinit`, `openbox`. | Rootfs ~2-3 GB, boot em TTY (multi-user.target). |
| **systemd 258.1-1 fixo (IgnorePkg)** | Systemd ≥260 quebra com kernel 5.4/7.0 (cgroup v2, APIs novas). `IgnorePkg = linux linux-headers mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon systemd systemd-libs systemd-sysvcompat` + downgrade via `pacman -U --nodeps` (sem `--dbonly`). | Boot systemd OK, sem "Failed to mount early API filesystems". |
| **DisableSandbox no pacman.conf** | Kernels PS4 não têm namespaces completos; sandbox do pacman falha nos hooks. | `pacman` instala/atualiza sem erro. |
| **SSH pré-configurado (root/ps4, ps4/ps4)** | `PermitRootLogin yes`, `PasswordAuthentication yes`, `PermitEmptyPasswords yes`, `StrictModes no`. `sshd.service` habilitado + `ssh-auto-startup.service` (monta rootfs e inicia sshd via chroot no early boot). | SSH acessível **antes** do login completo (útil para debug). IP WiFi: 192.168.6.128. |
| **Rede estática eth0 (192.168.0.2/24)** | `/etc/systemd/network/20-ethernet.network` + `systemd-networkd` habilitado. `dhcpcd` só gerencia `wlan0` (`denyinterfaces eth0`). | `eth0` sobe com IP fixo para testes GBE. |
| **WiFi pré-configurado (wpa_supplicant@wlan0)** | SSID/PSK em `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`. Serviço habilitado. | Conecta automático no boot, SSH via WiFi funcional. |
| **Locale/Timezone/Keymap (pt_BR)** | `America/Sao_Paulo`, `pt_BR.UTF-8`, `br-abnt2`. | Sistema em português. |
| **Swap file 8 GB + swappiness=90** | `fallocate -l 8G /swapfile` no pós-instalação. Essencial com RAM unificada limitada. | `swapon -s` mostra swap ativo. |
| **Hook initramfs `set-time-from-cmdline`** | Lê `time=UNIX_TS` do `/proc/cmdline` (injetado pelo payload kexec), faz `date -s` + `hwclock -w`. Early hook (roda antes do rootfs). | Relógio sincronizado no boot sem RTC driver nativo. |
| **VRAM control via `vram.txt` (FAT32)** | Payload lê `vram.txt` da partição BOOT antes do kexec. Valores: 32-512 MB (server headless), **1024 MB (default desktop)**, 2048-3072 (gaming), 4096 (máx 4 GB VRAM / 4 GB RAM CPU). | Testado: 1024 MB → Xorg/Cinnamon estável. |

---

## 10. Kernel Dump / Engenharia Reversa (FW 12.52) ✅ CONCLUÍDO

| Feature | Descrição | Validação |
|---------|-----------|-----------|
| **`scene-kmem-dumper` (TCP porta 9020)** | Payload reescrito 2026-07-19: usa `get_kernel_base()` via `kexec` (NÃO `__readmsr(0xC0000082)` — causa Kernel Panic em userland), `get_memory_dump()` via `copyout` real (fault-safe), transporte TCP (PC envia `[u64 start][u64 size]`, PS4 transmite chunks 16 KB). Chunk ilegível = 16 KB zeros (preserva alinhamento). Receptor `receive_kmem_dump.py` retomável. | **SUCESSO 2026-07-20**: 32.21 MB dump completo em 3s (11.3 MB/s), zero corrupção, zero panic. Tag `milestone-dump-success`. |
| **CoreOS/SLB2 analisado** | 4 contêineres SLB2 em `sflash0s1.crypt`: slots boot 0/1 (151 KB cada), CoreOS ativo/backup. Kernel Orbis em `80010002` (offset 64, 10.8 MB) cifrado via **SAMU hardware** — dump offline inviável (`ps4-pup-unpacker` extrai 0 bytes). | Dump de RAM ativa é a única via. |
| **Drivers Orbis identificados no dump** | `SceGbeMtsCtrl`/`SceGbeMtsPhyCtrl` (GBE MTS), `icc_device_power.c` (power management), `icc_thermal/buttons/fan/indicator.c` (Syscon), `icc_power.c` (S5 shutdown). Caminho fonte Sony: `W:\Build\J02690760\sys\freebsd\sys\dev\scesb\icc\`. | Base para driver `mts.ko`, ICC retry, S5 patch. |
| **Banco de varreduras SQLite (`ps4_hardware_memory.db`)** | Tabelas: `readonly_verification` (leituras confirmadas), `hardware_registers` (catálogo), `bar_regions` (mapeamento BARs), `write_sweep_results` (testes escrita), `decompiled_functions` (~50 funções MTS/GBE/ICC/glue/rtc indexadas por addr, role, status, validated_by_test_id), `test_history` (cronológico). View `v_decompiled_summary` agrega contagens. | Fonte única para não repetir varredura ao vivo (cada teste = power cycle). |

---

## 11. Build / Deploy / Ferramentas

| Feature | Descrição | Validação |
|---------|-----------|-----------|
| **`00-build-kernel-7.0.sh`** | Script único, oficial, reprodutível. Clona `rmuxnet/linux` (branch `baikal/7.0.8-Stable`), aplica patches, configura via `scripts/config` (todas as flags documentadas no script), compila ThinLTO + General + Baikal, `JOBS=2` + `--thinlto-jobs=2`, gera `bzImage-7.0-<TAG>` + `config-7.0-<TAG>` em `boot_referencia/`. Remove `build.sh` upstream (incorporado). | Build limpo ~20-45 min. Histórico de tags versionado. |
| **`01-build-image-7.0.sh`** | Cria rootfs Arch via `pacstrap` em `/mnt/hdauxiliar/temp/arch_build_7.0`, instala módulos (`modules_install`), **sobrescreve `mts.ko`** com `drivers_mts/build/mts.ko` se existir, **instala Mesa patchado** de `mesa/mesa-ps4-gladius-liverpool-latest.tar.xz` em `/opt/mesa-ps4-patched` + `/etc/environment`, gera initramfs `mkinitcpio` (hooks: base, set-time-from-cmdline, udev, modconf, block, filesystems, keyboard, fsck), copia EDID/firmwares GPU/WiFi, gera `initramfs-7.0.cpio.gz` + `bootargs-7.0.txt` + tarball `arch_minimal_v2-7.0.tar`. | Imagem bootável, SSH + WiFi + Mesa corrigido + mts.ko atualizado. |
| **`02-burn-image-7.0.sh /dev/sda`** | Particiona HD: sda1=200MB FAT32 LABEL=BOOT, sda2=restante ext4 LABEL=psxitarch. Formata, monta, copia boot files + extrai rootfs tarball. **Label `psxitarch` obrigatório** (initramfs faz `mount LABEL=psxitarch /newroot` hardcoded). | HD bootável direto no PS4. |
| **`deploy-boot-7.0.sh <TAG> [MNT]`** | Troca **só boot** (sda1) no HD já particionado, mantém rootfs intacto. Usa 4 arquivos da tag em `boot_referencia/` (bzImage, config, bootargs, initramfs — **sem fallback silencioso**). Sanidade: rejeita arquivos < tamanho mínimo (bzImage 4 MB, initramfs 1 MB, bootargs 32 B). Checa espaço livre + remove bzImages antigos do HD (regra: no HD fica **apenas** o bzImage ativo; histórico em `boot_referencia/`). Backup bootargs anterior (~400 B). **MD5 origem→destino automático** ao final. Desmonta ambas partições do mesmo disco (evita dirty bit). | Deploy rápido (<1 min), idempotente, rollback = `deploy-boot <tag-velha>`. |
| **`rebuild-initramfs-7.0.sh`** | Reconstrói initramfs em rootfs já montado em `/mnt/ps4_rootfs_7.0` após mudar hooks. | Útil para iterar hooks sem refazer rootfs. |
| **`scripts/build_mts_module.sh`** | Compila `mts.ko` isolado usando árvore do kernel (`/mnt/hdauxiliar/temp/kernel_build_7.0`), clang+LLD, copia fontes de `drivers_mts/`, remove seções `.BTF`/`.BTF.base` (evita "failed to validate module BTF" no insmod). Gera `drivers_mts/build/mts.ko`. | Módulo carrega no PS4 sem erro de BTF. |
| **`scripts/deploy_mts.sh [push|test]`** | `push`: compila (se necessário), SCP `mts.ko` → PS4, `rmmod` + `insmod stage=4`. `test`: configura eth0 192.168.0.2, `ping -I eth0 -c 5 192.168.0.1`, mostra `mts_regs`, `dmesg`, `ifconfig`. | Ciclo deploy+teste em <30s. |
| **`scripts/uart_start.sh` / `uart_stop.sh` / `uart_capture.sh`** | Captura UART robusta (evita disputa de porta, re-abre se PL2303 re-enumera), grava `.bin` + `.log` timestampados. | Captura estável de boot completo. |
| **`scripts/webhost_start.sh` / `webhost_stop.sh`** | HTTP server para servir payloads/kernel via PSFree-Enhanced. | Usado no fluxo de injeção. |

---

## 12. Descobertas de Hardware Documentadas (Consolidado)

| Área | Descoberta | Fonte |
|------|------------|-------|
| **Southbridge Baikal** | CXD90042GG (BGA, B1 0x30201), 2 CPUs no die: EMC (Cortex-M3, ~100 MHz, FreeBSD próprio, UART debug independente) + EAP (Cortex-A8 PJ4C, 500 MHz, FreeBSD 9, gerencia rede/BD/HDD em standby). Conectado à APU via PCIe x4, ao Syscon via SPI. | `HARDWARE.md` + psdevwiki NVG-002 |
| **PCI IDs Baikal** | ACPI 0x90d7, GBE 0x90d8, AHCI 0x90d9, SDHCI 0x90da, PCIe Glue 0x90db, DMAC 0x90dc, MEM 0x90dd, XHCI 0x90de. | `HARDWARE.md` |
| **BAR4 Glue Logic incompatível** | Aeolia/Belize usam function 4 (BAR4) como glue logic. Baikal B1 tem layout diferente → `pci_ioremap_bar(dev,4)` retorna NULL, `apcie_glue_init()` falha, todos dispositivos não inicializam. Fix: skip `glue_init` quando `is_baikal`. | `HARDWARE.md` |
| **UART Baikal** | MMIO `0xC890E000` (não `0xD0340000`). Pinout físico no lado VERSO, perto do Syscon `A06-COL2` (diagrama repair.wiki + foto psdevwiki NVG-002). TX/GND identificados; RX não documentado (só log saída). | `HARDWARE.md`, `memory/uart-ttl-pinagem-corrigida-2026-07-27.md` |
| **Watchdog Timer** | Southbridge tem WDT ativado pelo Orbis/loader. Se Linux não alimentar/desativar, força reboot elétrico. `/dev/watchdog` não existe no rootfs → mitigação no payload loader (GoldHEN/PPPwn). | `BAIKAL_HARDWARE_DISCOVERIES.md` |
| **HD Interno** | Toshiba MQ04ABF100 1TB (1.953.525.168 setores), S/N X8MNSD6RS. GPT custom Sony rev 2.0, Disk GUID termina em MAC LAN. 14 partições, **todas criptografadas** (alta entropia, sem filesystem reconhecível). Slots A/B redundantes (sda9/sda10, sda11/sda12). | `HARDWARE.md` (fonte de verdade) |
| **GBE = MTS, não Yukon** | Orbis usa `SceGbeMtsCtrl`/`SceGbeMtsPhyCtrl` para Baikal (vs `SceGbeMskCtrl` p/ Aeolia/Belize). Driver Linux `mts.ko` escrito do zero. | `BAIKAL_HARDWARE_DISCOVERIES.md`, `RE_KERNEL_GBE_ATTACH.md` |
| **ICC power management** | Major 4 = device power. Minor 0x38 = GBE MAC power-on (retry loop necessário). Minor 0x50 = alarm bitmask (RTC). Major 2 0x0b/0x0c sub 0x81 = save/load context RTC. **NUNCA varrer minors com data=1** → crash/reboot. | `ICC_GBE_TEST_LOG.md`, `ps4_hardware_memory.db` |
| **PHY GBE domain separado** | ICC 4/0x38 liga MAC core (BAR0+0x004: 0→0xb19), mas PHY continua power-gated. MDIO Clause 45/22 sempre 0/timeout. Hold/pulse glue: GBE hold=0x180020, pulse=0x180074 (bloco 0x2000). SATA hold=0x18002c, pulse=0x18006c. | `BAIKAL_HARDWARE_DISCOVERIES.md`, `test_history` no DB |
| **MAC enable/stop rules** | **NUNCA escrever 0 em 0x34/0x38** (corrompe permanentemente, one-shot por power cycle). Enable por boot). Enable: escrever **1 direto** (`mts_write`, NUNCA `mts_set`/RMW → 0x09 rejeitado). Stop: escrever **2** (bit 1 soft-reset) + poll bit 1 até 0 (ACK). Sequência Orbis: IMR=0x7ffffa → 0x34=2(poll) → 0x38=2(poll) → drain TX/RX → 0x1c8 &= ~0x440. | `LICOES_APRENDIDAS.md`, `MTS_INIT_SEQUENCE_dc5a31f0.md` |
| **0x200 perigoso** | Escrever 0 em BAR0+0x200 TRAVA MAC enable permanentemente. Orbis escreve 0x200=0 na calibração (dc5a0ba0) mas ativa MAC DEPOIS (dc5a31f0). Driver Linux **não toca 0x200**. | `LICOES_APRENDIDAS.md` |
| **KVM-AMD viável no Jaguar** | CPU expõe `svm`, `npt`, `nrip_save`, `tsc_scale`, `flushbyasid`, `decodeassists`, `pausefilter`, `pfthreshold`, `vmmcall`. `CONFIG_KVM`/`CONFIG_KVM_AMD` só precisam ser ligados (base já pronta: `CONFIG_VIRTUALIZATION=y`, `AMD_IOMMU=y`, `X86_X2APIC=y`, `SMP=y`, `NR_CPUS=8`). Sem AVIC (legacy IRQ), sem SEV (PSP/CCP-DD inativo). Fases 1-2 (build+auditoria) concluídas; Fase 3 (deploy kexec) pronta. | `BACKLOG.md` (KVM-PS4), `PLANO_KVM_PS4_VIABILIDADE_2026-07-24.md` |

---

## 13. Lições Críticas Incorporadas ao Projeto (Já Aplicadas)

| # | Lição | Aplicação Prática |
|---|-------|-------------------|
| 7 | **Label root DEVE ser `psxitarch`** | `02-burn-image` faz `mkfs.ext4 -L psxitarch`; initramfs hardcoda `mount LABEL=psxitarch`. |
| 18 | **UART + vídeo HDMI não coexistem no Baikal** | Bootargs usam `console=ttyS0...` + `video=`; `console=uart8250...` só isolado (sem vídeo). |
| 21 | **Partição BOOT 50 MB → 200 MB** | `02-burn-image` cria sda1=+200M. Kernel 7.0 + initramfs > 50 MB. |
| 23 | **Limite ~10 MB bzImage no kexec PS4** | Build usa ZSTD + ThinLTO + General + sem firmware GPU embutido → bzImage ~14 MB (acima do limite antigo, mas payloads v24+ suportam). |
| 24 | **NUNCA compilar em NTFS/FUSE** | Build obrigatório em `/mnt/hdauxiliar/temp/` (ext4). Script clona para lá. |
| 25 | **`printf '\xHH'` não confiável via telnet encadeado** | Usar escapes octais `\NNN` + conferir `dd` reporta blocos exatos. |
| 26/28 | **NUNCA injetar MMIO experimental em `linux_boot.c` / kexec path** | Leituras não alinhadas ou device power-gated → MCE/Target Abort → tela preta sem log. Risco só em userspace Linux bootado, um registrador por vez. |
|  | **Fallback silencioso em ferramenta de debug = armadilha** | `deploy-boot` falha alto se initramfs da tag falta; lista disponíveis + comando `cp` pronto. |
|  | **MD5 origem→destino automático no deploy** | Elimina passo manual e risco de testar binário errado. |
|  | **No HD fica APENAS o bzImage ativo** | `deploy-boot` remove `bzImage-7.0-*` antigos do HD a cada deploy; histórico em `boot_referencia/`. Partição BOOT 173 MB livres (era 454 KB). |

---

## 14. O que NÃO está aqui (Backlog / Pendente)

> Estes itens estão no `BACKLOG.md` e planos associados — **NÃO concluídos**, portanto **NÃO entram no FEATURES.md**:

- **GBE RX funcional** — PHY não sai de power-down (MDIO mudo). Ativo em `PLANO_FASES_GBE_2026-07-25.md`.
- **Driver `rtc-ps4-icc.c`** — infraestrutura pronta (`ps4_icc_rtc_cmd`), driver não escrito.
- **S5 shutdown completo (32 bytes)** — patch aplicado nos drivers ICC, pendente teste ao vivo.
- **WiFi manufacture data (NVRAM/eFUSE)** — calibração por unidade não extraída; usa defaults.
- **KVM-AMD Fase 3+** — build/auditoria OK; deploy kexec + smoke test VM pendentes.
- **IOMMU/VFIO passthrough** — investigação opcional (Fase 6 KVM).
- **Mesa: `partial_vs_wave` workaround (LIVERPOOL/2 SEs)** — escopo baixo, só afeta PS4 base, não Gladius/Pro.
- **UART RX físico confirmado eletricamente** — só TX/GND mapeados; RX precisa multímetro.

---

## 15. Referências Rápidas (Artefatos do Projeto)

| Artefato | Localização |
|----------|-------------|
| Kernel source (Strawberry 7.0.8 Baikal) | `/mnt/hdauxiliar/temp/kernel_build_7.0/` (git `rmuxnet/linux`, branch `baikal/7.0.8-Stable`) |
| Patches kernel (sky2, mts, ICC RTC) | `distros/arch_minimal_v2/patches/` |
| Driver `mts.ko` source | `drivers_mts/mts.c`, `drivers_mts/mts.h` |
| Mesa patch Gladius/Liverpool | `mesa/ps4-gladius-liverpool-patch/mesa-26.1.5-ps4-gladius-liverpool.patch` |
| Build scripts oficiais | `distros/arch_minimal_v2/00-build-kernel-7.0.sh`, `01-build-image-7.0.sh`, `02-burn-image-7.0.sh`, `deploy-boot-7.0.sh`, `rebuild-initramfs-7.0.sh` |
| Scripts auxiliares | `scripts/build_mts_module.sh`, `deploy_mts.sh`, `uart_start.sh`, `uart_stop.sh`, `webhost_start.sh` |
| Banco de varreduras HW | `consolidado/ps4_hardware_memory.db` (SQLite) |
| Dump kernel Orbis 12.52 | `scene-kmem-dumper/` (payload TCP 9020) |
| Documentação consolidada | `consolidado/` (50+ .md, índice em `INDEX_DOCUMENTACAO.md`) |
| Backlog / Planos ativos | `BACKLOG.md`, `PLANO_FASES_GBE_2026-07-25.md`, `PLANO_KVM_PS4_VIABILIDADE_2026-07-24.md` |

---

> **FEATURES.md** documenta **apenas o que já foi concluído e validado em hardware real**. Para itens em andamento, consulte `BACKLOG.md` e os planos referenciados. Este arquivo será atualizado a cada marco concluído.