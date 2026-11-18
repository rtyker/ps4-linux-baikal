# PS4 Linux — Baikal

Linux running natively on PlayStation 4 hardware with the **Baikal** southbridge (developed and tested on a PS4 Pro),
loaded via `kexec` from a jailbreak payload (PSFree/GoldHEN) — with no dependency on
Sony software after the handoff.

> ⚠️ **Requires an already jailbroken PS4 on a compatible firmware.** This project neither teaches
> nor provides a jailbreak. For educational and research use in reverse engineering and embedded systems.

> **New:** the root filesystem now also boots from the PS4's internal disk, with no USB drive attached — see [RELEASE_NOTES.md](RELEASE_NOTES.md).

## Two tracks

The repository is split into two independent tracks with a single explicit dependency:
the distro consumes the boot artifacts that the kernel produces.

| Track | Folder | What it does | README |
|---|---|---|---|
| **1 — Baikal Kernel 7.0** | [`kernel/`](kernel/) | Builds the `7.0.8-Strawberry-ThinLTO-Baikal-+` kernel and maintains the patches, the `mts.ko` driver, the source tree, the diagnostics (UART/netconsole) and **all of the reverse engineering** (SQLite, decompiled code, notes, plans) | [`kernel/README.md`](kernel/README.md) |
| **2 — Baikal Linux Distro** | [`distro/`](distro/) | Builds the minimal Arch rootfs + initramfs, writes it to the drive, deploys the boot files, handles firmware/patched Mesa, PFS partition mounting, and releases | [`distro/README.md`](distro/README.md) |

```
kernel/00-build-kernel-7.0.sh  ──(bzImage, per-tag config)──►  distro/boot_referencia/  ──►  distro/deploy-boot-7.0.sh
```

No other dependency crosses the tracks: the distro never builds a kernel, and the kernel knows
nothing about the rootfs. `PS4_BOOT_REF` lets you point the distro at a different set of artifacts.

## Current status — what works

| Subsystem | Status | Details |
|---|---|---|
| **Boot** | ✅ | `kexec` → kernel 7.0 → initramfs → Arch rootfs |
| **Video (HDMI)** | ✅ | 1080p@60, Gladius GPU via `amdgpu` (Mesa patched to recognize the chip). The internal DisplayPort link to the Panasonic MN864729 bridge still logs `clock recovery failed` on every modeset, yet the picture comes up and stays stable (see below) |
| **Boot from the internal disk** | ✅ | `bzImage`, `initramfs.cpio.gz`, `bootargs.txt` and `vram.txt` live in `/data/linux/boot/` on the console's drive, uploaded over FTP by `distro/deploy-boot-ftp-7.0.sh`. Confirmed on a real console on 2026-11-17 |
| **Root filesystem on the internal disk** | ✅ | A 16 GiB ext4 image inside `sda27`, mapped through `dm-crypt` + `dm-linear` by the `ps4-internal-root` initramfs hook; no USB drive needed. Six consecutive cold boots without USB, automatic fallback to the USB root, Orbis data untouched. See below |
| **VRAM size** | ✅ | Set by a `vram.txt` file (value in MB) in the BOOT partition, which overrides the loaded payload. Measured: 1024 → 6911 MiB RAM, 2048 → 5903 MiB, 4096 → 3893 MiB; the carve-out comes out of the single 8 GiB GDDR5 pool shared by CPU and GPU. The payload caps it at 4096 MB |
| **Audio (HDMI)** | ⚠️ | `snd_hda_intel` exposes the HDMI devices, but actual sound has not been re-tested since the Display Core was removed from the build |
| **3D GPU** | ✅ | OpenGL 4.5, Vulkan 1.3 (RADV) |
| **SSH (WiFi admin)** | ✅ | `root@192.168.6.128`, starts automatically |
| **Internal SATA (real HDD)** | ✅ | Stable `ata1` via a 1 ms polling timer on PCI function `.7` (`xhci_aeolia`) — validated live on tag `20260730-sata-polling-fase-ab`; the `v1.0.0` build contains the mechanism but has no recorded validation boot |
| **USB 3.0 / SD-MMC** | ✅ | `xhci_aeolia` / `sdhci` |
| **KVM-AMD** | ✅ | `/dev/kvm` answers real ioctls (SVM, NPT, nested). QEMU 11.1.3 (`qemu-base`) in the rootfs; a 512-byte guest running under `-accel kvm` writes to the serial port and halts correctly |
| **Baikal Memory / SPM (`00:14.6`)** | ✅ | In-house in-tree `baikal-memory.ko` driver: exposes `/dev/baikal-memory` (0600) and sysfs, reads the real factory MAC (`2c:cc:44:3f:69:5f`) and the ICC mailbox region, and supports controlled writes guarded by a parameter (`allow_write=0`) in the DDR3 window (BAR2). Reads and writes now go through the southbridge DMA controller: 545–638 MB/s against ~4 MB/s by CPU. 46/46 live checks pass, including injected DMAC faults |
| **Swap on the SPM/DDR3 (`baikal-spm-blk`)** | ✅ | `/dev/baikal_spm0`, a 180 MiB block device on the SPM moved by DMA and used as swap (priority 50, below zram). ~20x faster than CPU access on real swap traffic, 0 corrupted blocks in the live tests; starts automatically at boot. See [`RELEASE_NOTES.md`](RELEASE_NOTES.md) |
| **Internal HDD mount (read-only)** | ✅ | The Orbis partitions `sda27` (user, UFS2, 884 GiB), `sda29` and `sda25` mount read-only with the user's own EAP key (never committed; installed under `/etc/ps4-keys/`). Write support is deliberately not used |
| **RTC via ICC** | ✅ | `/dev/rtc0` via `rtc-ps4-icc`; `hwclock -r` works (validated live on tag `20261115-hwclock-min`). The hardware exposes no readable time source, so the RTC is seeded from the system clock and kept in sync by NTP; no reset to 1970 on boot |
| **NTP time sync** | ✅ | `chrony` against NTP.br (`a/b/c/d.st1.ntp.br`), offset < 1 ms, clock correct at boot. `systemd-timesyncd` is not used: `wlan0` is managed by dhcpcd, so networkd reports `ONLINE_STATE=offline` and timesyncd never queries a server |
| **Bluetooth** | ✅ | `btmtksdio` (MediaTek MT7668, SDIO): working perfectly. User-tested on 2026-11-13 |
| **Bluetooth audio** | ✅ | Playback on a Bluetooth speaker working perfectly. User-tested on 2026-11-13 |
| **Gamepad** | ✅ | Working perfectly. User-tested on 2026-11-13 (model and connection method not recorded) |
| **Southbridge DMA (`00:14.5`)** | ✅ | In-house `baikal-dmac` v0.1 `dmaengine` driver (2 channels, memcpy via chained descriptors): validated live with the kernel's `dmatest`, **3000 tests, 0 failures**. Loads as a module (`virt-dma` + `baikal-dmac`); channel 2 completes by polling (its IRQ never arrives). It now powers the `baikal-memory` and swap transfers above |
| **Wired Ethernet (`eth0`)** | ⚠️ partial | In-house `mts.ko` driver brings up the MAC and DMA, but the PHY never leaves power-down (firmware blocker, investigation closed) |
| **Full power-off (S5)** | ✅ | `poweroff`, `shutdown -h now` and `reboot` are all confirmed working: the console powers off completely (blue light and fan stop). Closed on 2026-11-16 (tag `20261116-s5-dma`) |
| **Baikal HPET clocksource / watchdog** | ⏸️ paused | Patches are applied by the build but `CONFIG_CLKSRC_BAIKAL_HPET` and `CONFIG_WATCHDOG` are off: a build with both enabled gave a black screen twice, and a later isolated clocksource test read the wrong register block (the driver maps the start of BAR2 instead of `BAR2 + 0x109000`, unconfirmed). Work is on hold, see `BACKLOG.md` |

### 🌟 Highlight: Linux root filesystem on the internal disk (no USB)

The root filesystem runs from a 16 GiB ext4 image that is a **regular file** inside the Orbis user partition (`sda27`) — no repartitioning and no changes to games or saves. Orbis itself created the file over FTP, with a per-sector index and nonce written into every sector. Linux reads the UFS2 block map with `FIBMAP` (read-only), checks every mapped sector against that pattern once, and then writes only through `dm-crypt` → `dm-linear` (`/dev/mapper/ps4root`). The `ps4-internal-root` initramfs hook re-checks the table checksum and the ext4 UUID at every boot; if anything fails it leaves `root=LABEL=psxitarch` alone and the USB root comes up instead.

Validated on a PS4 Pro (Baikal) with the stock HDD: six consecutive cold boots without USB, a forced fallback with a corrupted checksum, and a clean Orbis check afterwards. 1 GiB writes averaged ~75 MB/s on the internal HDD versus ~279 MB/s on the USB SSD (five runs each). Not the first internal-root boot ever reported on Baikal — the novelty here is the sector-ownership proof, the automatic fallback and the validation on this hardware. Runbook and sources: [`others/docs/PLAN_INTERNAL_ROOTFS.md`](others/docs/PLAN_INTERNAL_ROOTFS.md).

### 🌟 Reverse Engineering Highlight: Baikal Memory Driver (SPM/DDR3)
The Baikal southbridge has a dedicated auxiliary DDR3 memory (Scratch Pad Memory, SPM, PCI `00:14.6`) that previously had no Linux support at all. The project built the `baikal-memory` driver from scratch:
* **Hardware mapping:** BAR0 (4 KiB MMIO), BAR2 (1 GiB advertised, but only the first 188 MiB answer on the tested PS4 Pro; the driver probes this at load time), BAR4 (1 MiB), BAR5 (256 KiB Mailbox/ICC/Bootparams).
* **Hardware identity:** Runtime extraction of the factory MAC address (`BAR5+0x2f000`).
* **Syscon/ICC bridge:** Safe mapping of the message area shared with the Syscon (`BAR5+0x2c000`).
* **Safety and idempotency:** Module with guarded writes (`allow_write=0`), a strict whitelist for the BAR2 window, and idempotent integration into kernel 7.0 via patch.

Details, root causes, and what has already been ruled out: [`others/docs/BACKLOG.md`](others/docs/BACKLOG.md).

## Release Notes

### 2026-11-17 — Root filesystem on the internal disk
Linux now boots entirely from the console's own drive, without USB. The root is a 16 GiB ext4 image inside `sda27`, mounted through `dm-crypt`/`dm-linear` by an initramfs hook with a USB fallback. See [`RELEASE_NOTES.md`](RELEASE_NOTES.md) and [`others/docs/PLAN_INTERNAL_ROOTFS.md`](others/docs/PLAN_INTERNAL_ROOTFS.md).

### 2026-11-17 — Boot the kernel from the internal disk
The kernel and initramfs can now boot from the console's own drive (`/data/linux/boot/`), with a safe FTP deploy script and a boot-source marker; this step was done first, while the root filesystem still lived on USB. See [`RELEASE_NOTES.md`](RELEASE_NOTES.md) and [`others/docs/BOOT_FROM_INTERNAL_DISK.md`](others/docs/BOOT_FROM_INTERNAL_DISK.md).

### 2026-11-17 — Swap on the SPM/DDR3 by DMA
The SPM now serves as a fast swap device through the southbridge DMA controller (`baikal-spm-blk`), with before/after numbers and credits in [`RELEASE_NOTES.md`](RELEASE_NOTES.md). The same tag carries the DP link at 2.7 Gbps (`ps4-dp-link-rate-270000.patch`), which is live-tested but does **not** make the DisplayPort `clock recovery` pass: the sink is powered, configured and receives the TPS1 request, but never reports lock. That front is paused; measurements are in `others/docs/BACKLOG.md`.

### 2026-11-16 (Tag `20261116-keep-mode-aplicado`)

**Video Bridge Panasonic MN864729 now functional** — pure console (no Xorg) stable for 1h45m+ idle.

Two patches applied to the bridge driver (`drivers/gpu/drm/amd/amdgpu/ps4_bridge.c`):

1. **`ps4-bridge-dp-init.patch`** — Enables the DisplayPort-side initialization sequence for the Panasonic MN864729 bridge (HDMI retimer). The sequence was previously disabled with the comment: *"No idea. DP stuff probably. This borks for some reason. Meh."* Now active, it allows DP link training to proceed correctly.

2. **`ps4-bridge-keep-mode.patch`** — In `post_disable` (DPMS off / console blank), the driver no longer zeroes `mn_bridge->mode`. Instead it sets an `idle` flag to preserve the mode state. On the next `enable` (DPMS on / console unblank), this prevents the *"mode not available"* error that previously left the screen permanently black after idle/screensaver.

**Validated on real PS4 hardware (PS4 Pro, Baikal southbridge):**
- Pure console framebuffer (`amdgpudrmfb`) stable for 1h45m+ with `consoleblank=0`
- HDMI connector `HDMI-A-1` reports `connected`, modes `1920x1080` and `1280x720` available
- DP link training active (visible in `dmesg` as `amdgpu_atombios_dp_link_train`)
- Driver built into kernel (symbols present in `/proc/kallsyms`)

**Artifacts:** `distro/boot_referencia/*-7.0-20261116-keep-mode-aplicado*` (bzImage, config, bootargs, initramfs, `.build-complete`).  
**Rollback:** `sudo ./deploy-boot-7.0.sh 20261116-keep-mode-aplicado` (boot-only, keeps rootfs).

---

## Release

[`distro/RELEASE/`](distro/RELEASE/) holds the **v1.0.0** distribution release (`bzImage`,
`bootargs`, `initramfs`, `config` + deploy README and MD5) and the history of promoted tags.

## Getting started

```bash
# 1) Kernel (track 1)
cd kernel && sudo ./00-build-kernel-7.0.sh <TAG>

# 2) Distro (track 2)
cd ../distro
sudo ./01-build-image-7.0.sh          # Arch rootfs + initramfs
sudo ./02-burn-image-7.0.sh /dev/sdX  # partitions and writes (label psxitarch!)
sudo ./deploy-boot-7.0.sh <TAG>       # or just swap the boot files, keeping the rootfs
./scripts/promote-release.sh <TAG>    # promotes a live-tested tag
```

### Configuração do ambiente de desenvolvimento (opcional)

Para builds locais com seu usuário não-root, chave SSH e chave EAP do HD interno,
use a pasta **`.localdev/`** (não versionada, no `.gitignore`):

```bash
# 1) Copie o modelo de configuração
cp .localdev/user_config.env.example .localdev/user_config.env

# 2) Edite com seus valores
vim .localdev/user_config.env
#   - LOCAL_USER="seu_usuario"        (ex: "dev", "ps4dev")
#   - LOCAL_UID="1001"
#   - LOCAL_SSH_PUBKEY_FILE="$HOME/.ssh/id_ed25519.pub"
#   - LOCAL_EAP_KEY_FILE=".localdev/ps4-keys/eap_hdd_key.bin"

# 3) Gere/obtenha as chaves necessárias
#    SSH (se não tem):
#      ssh-keygen -t ed25519 -C "seu_email@exemplo.com"
#    EAP key do HD interno (OBRIGATÓRIA para --internal-root):
#      • No Orbis + GoldHEN: execute payload EAPDumper (porta 9090)
#      • Puxe via FTP (porta 2121) → salva como .localdev/ps4-keys/eap_hdd_key.bin
#      • Verifique: stat -c %s .localdev/ps4-keys/eap_hdd_key.bin  # deve dar 32

# 4) Source as variáveis e rode o build
source .localdev/user_config.env
sudo -E ./distro/01-build-image-7.0.sh <TAG> --incremental

# 5) Deploy com internal-root (rootfs no HD interno):
LOCAL_EAP_KEY_FILE=.localdev/ps4-keys/eap_hdd_key.bin \
  ./distro/deploy-boot-ftp-7.0.sh <TAG> --internal-root
```

> **Detalhes completos:**
> - `.localdev/user_config.env.example` — modelo comentado com todas as variáveis
> - `.localdev/ps4-keys/README.md` — como obter a chave EAP, formato, verificação
> - `.localdev/README.md` — visão geral da pasta

Full rules (patch idempotency, mandatory snapshots, `bootargs` conventions,
deploy procedure, SSH, UART, RE database): [`AGENTS.md`](AGENTS.md) — the single source of truth;
`CLAUDE.md` only imports that file.

## Legal notice

Research/reverse engineering on hardware the author owns. The repository does not include or distribute
firmware, keys, or proprietary binaries from Sony — only artifacts originated here (Linux kernel, in-house
drivers, scripts, and documentation).
