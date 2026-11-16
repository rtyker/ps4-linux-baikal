# PS4 Linux — Baikal (CUH-2xxx)

Linux running natively on PlayStation 4 Slim hardware (**Baikal** SoC, CUH-2xxx),
loaded via `kexec` from a jailbreak payload (PSFree/GoldHEN) — with no dependency on
Sony software after the handoff.

> ⚠️ **Requires an already jailbroken PS4 on a compatible firmware.** This project neither teaches
> nor provides a jailbreak. For educational and research use in reverse engineering and embedded systems.

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
| **Video (HDMI)** | ✅ | 1080p@60, Gladius GPU via `amdgpu` (Mesa patched to recognize the chip) |
| **Audio (HDMI)** | ✅ | `snd_hda_intel` |
| **3D GPU** | ✅ | OpenGL 4.5, Vulkan 1.3 (RADV) |
| **SSH (WiFi admin)** | ✅ | `root@192.168.6.128`, starts automatically |
| **Internal SATA (real HDD)** | ✅ | Stable `ata1` via a 1 ms polling timer on PCI function `.7` (`xhci_aeolia`) — validated live on tag `20260730-sata-polling-fase-ab`; the `v1.0.0` build contains the mechanism but has no recorded validation boot |
| **USB 3.0 / SD-MMC** | ✅ | `xhci_aeolia` / `sdhci` |
| **KVM-AMD** | ✅ | `/dev/kvm` answers real ioctls (SVM, NPT, nested). QEMU 11.1.3 (`qemu-base`) in the rootfs; a 512-byte guest running under `-accel kvm` writes to the serial port and halts correctly |
| **Baikal Memory / SPM (`00:14.6`)** | ✅ | In-house in-tree `baikal-memory.ko` v0.2 driver: exposes `/dev/baikal-memory` (0600) and sysfs, reads the real factory MAC (`2c:cc:44:3f:69:5f`) and the ICC mailbox region, and supports controlled writes guarded by a parameter (`allow_write=0`) in the DDR3 window (BAR2) |
| **RTC via ICC** | ✅ | `/dev/rtc0` via `rtc-ps4-icc`; `hwclock -r` works (validated live on tag `20261115-hwclock-min`). The hardware exposes no readable time source, so the RTC is seeded from the system clock and kept in sync by NTP; no reset to 1970 on boot |
| **NTP time sync** | ✅ | `chrony` against NTP.br (`a/b/c/d.st1.ntp.br`), offset < 1 ms, clock correct at boot. `systemd-timesyncd` is not used: `wlan0` is managed by dhcpcd, so networkd reports `ONLINE_STATE=offline` and timesyncd never queries a server |
| **Bluetooth** | ✅ | `btmtksdio` (MediaTek MT7668, SDIO): working perfectly. User-tested on 2026-11-13 |
| **Bluetooth audio** | ✅ | Playback on a Bluetooth speaker working perfectly. User-tested on 2026-11-13 |
| **Gamepad** | ✅ | Working perfectly. User-tested on 2026-11-13 (model and connection method not recorded) |
| **Southbridge DMA (`00:14.5`)** | ✅ | In-house `baikal-dmac` v0.1 `dmaengine` driver (2 channels, memcpy via chained descriptors): validated live with the kernel's `dmatest`, **3000 tests, 0 failures**. Loads as a module (`virt-dma` + `baikal-dmac`); channel 2 completes by polling (its IRQ never arrives). Practical usefulness is still modest, see `BACKLOG.md` |
| **Wired Ethernet (`eth0`)** | ⚠️ partial | In-house `mts.ko` driver brings up the MAC and DMA, but the PHY never leaves power-down (firmware blocker, investigation closed) |
| **Full power-off (S5)** | ⚠️ partial | `poweroff` shuts down the OS; the blue light does not turn off by itself |
| **Baikal HPET clocksource / watchdog** | ⏸️ disabled | Patches are applied by the build but `CONFIG_CLKSRC_BAIKAL_HPET` and `CONFIG_WATCHDOG` are off by default: a build with both enabled gave a black screen twice (UART stops at `kexec: About to relocate and jump to kernel`; root cause unconfirmed). Pending isolated tests, see `BACKLOG.md` |

### 🌟 Reverse Engineering Highlight: Baikal Memory Driver (SPM/DDR3)
The Baikal southbridge (PS4 Slim) has a dedicated auxiliary 256 MB DDR3 memory chip (Scratch Pad Memory, SPM, PCI `00:14.6`) that previously had no Linux support at all. The project built the `baikal-memory` driver from scratch:
* **Hardware mapping:** BAR0 (4 KiB MMIO), BAR2 (256 MB DDR3), BAR4 (1 MiB), BAR5 (256 KiB Mailbox/ICC/Bootparams).
* **Hardware identity:** Runtime extraction of the factory MAC address (`BAR5+0x2f000`).
* **Syscon/ICC bridge:** Safe mapping of the message area shared with the Syscon (`BAR5+0x2c000`).
* **Safety and idempotency:** Module with guarded writes (`allow_write=0`), a strict whitelist for the BAR2 window, and idempotent integration into kernel 7.0 via patch.

Details, root causes, and what has already been ruled out: [`others/docs/BACKLOG.md`](others/docs/BACKLOG.md).

## Release Notes — 2026-11-16 (Tag `20261116-keep-mode-aplicado`)

**Video Bridge Panasonic MN864729 now functional** — pure console (no Xorg) stable for 1h45m+ idle.

Two patches applied to the bridge driver (`drivers/gpu/drm/amd/amdgpu/ps4_bridge.c`):

1. **`ps4-bridge-dp-init.patch`** — Enables the DisplayPort-side initialization sequence for the Panasonic MN864729 bridge (HDMI retimer). The sequence was previously disabled with the comment: *"No idea. DP stuff probably. This borks for some reason. Meh."* Now active, it allows DP link training to proceed correctly.

2. **`ps4-bridge-keep-mode.patch`** — In `post_disable` (DPMS off / console blank), the driver no longer zeroes `mn_bridge->mode`. Instead it sets an `idle` flag to preserve the mode state. On the next `enable` (DPMS on / console unblank), this prevents the *"mode not available"* error that previously left the screen permanently black after idle/screensaver.

**Validated on real PS4 hardware (CUH-2xxx, Baikal SoC):**
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

Full rules (patch idempotency, mandatory snapshots, `bootargs` conventions,
deploy procedure, SSH, UART, RE database): [`AGENTS.md`](AGENTS.md) — the single source of truth;
`CLAUDE.md` only imports that file.

## Legal notice

Research/reverse engineering on hardware the author owns. The repository does not include or distribute
firmware, keys, or proprietary binaries from Sony — only artifacts originated here (Linux kernel, in-house
drivers, scripts, and documentation).
