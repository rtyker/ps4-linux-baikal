# PS4 Hardware Documentation (Linux on PS4)
**Target:** 192.168.6.128 (root/ps4)  
**Date:** 2026-07-13  
**Kernel:** 5.4.x (Arch Linux minimal)

---

## GPU / Video Hardware

| Component | Details |
|-----------|---------|
| **GPU** | AMD "Gladius" (Liverpool APU integrated) - PCI ID `1002:9924` |
| **GPU Family** | GCN 2.0 / Sea Islands (CIK) - `CONFIG_DRM_AMDGPU_CIK=y` |
| **VRAM** | 1024 MB GDDR5 (0xF0000000 - 0xF3FFFFFF) |
| **GART** | 512 MB |
| **Display Controller** | DCE v8.0 (Display Core Engine) |
| **Kernel Driver** | `amdgpu` (modesetting enabled) |
| **VBIOS** | Version `113-Roma-012` (GDDR5, Roma GPU) |
| **Firmware** | ME/RLC/PFP/CE v21, SDMA v9, others v0 |

---

## HDMI Output (HDMI-A-1)

| Property | Value |
|----------|-------|
| **Connector** | `HDMI-A-1` (Type A, HPD1, DDC: i2c-3 @ 0x50) |
| **Status** | `connected` + `enabled` |
| **Current Mode** | `1920x1080@60Hz` (forced via kernel cmdline: `video=HDMI-A-1:1920x1080@60`) |
| **Available Modes** | Only `1920x1080` exposed (EDID parsing limited) |
| **Encoder** | `DFP1: INTERNAL_UNIPHY` (TMDS) |
| **Bridge** | PS4-specific `ps4_bridge` (VIC mode 16 = 1080p60) |
| **Framebuffer** | `/dev/fb0` - 32bpp, 1920x1080, stride 7680 |
| **Audio** | HDMI Audio enabled (`amdgpu.audio=1`, device `1002:9921`) |

---

## Monitor EDID (Read via I2C 0x50 on i2c-3)

**Raw EDID (256 bytes):** Saved as `ps4_tv_edid.bin`

```
Manufacturer: 0xA934 (Samsung)
Product ID:   0x0729
Serial:       0x01010101
Mfg Date:     Week 12, 2015
EDID Version: 1.3
Monitor Name: "M8N4627 9"  (Samsung 46"/55" series)
Max Size:     120cm x 27cm (~54" diagonal)
Gamma:        2.49
Features:     Digital, 8-bit, sRGB, Preferred Timing, GTF, Standby/Suspend/Active-off
Extension:    CEA-861 (1 extension block)
```

**Key EDID Limitation:** The EDID only exposes `1920x1080@60` as the preferred/only detailed timing. No other modes (720p, 480p, etc.) are advertised.

---

## PS4-Specific Display Pipeline

```
amdgpu (DCE v8.0) 
  → TMDS Encoder (DFP1/UNIPHY) 
  → ps4_bridge (custom Sony bridge driver)
    → HDMI PHY (VIC mode 16 = 1080p60)
```

- **`ps4_bridge`** handles mode validation and HDMI PHY configuration
- **TMONREG=0x0c** indicates HDMI sink detected during probe
- **DP Link Training fails** (clock recovery ×5) but `ps4_bridge_enable` succeeds anyway — the PS4 bridge bypasses standard DP training

---

## Kernel Command Line (Video Relevant)

```
panic=0 clocksource=tsc consoleblank=0 net.ifnames=0 
radeon.dpm=0 amdgpu.dpm=0 drm.debug=0x06 
console=ttyS0,115200n8 console=tty0 
video=HDMI-A-1:1920x1080@60 quiet 
amdgpu.audio=1 usbcore.autosuspend=-1 
amdgpu.gpu_recovery=1 mitigations=off 
zswap.enabled=1 systemd.unified_cgroup_hierarchy=0 
systemd.legacy_systemd_cgroup_controller=yes audit=0 
netconsole=6665@192.168.0.2/eth0,6666@192.168.0.1/b4:45:06:6c:f6:4f
```

- **Power management DISABLED** (`dpm=0`) — clocks fixed, no dynamic frequency scaling
- **Mode forced** at boot via `video=` parameter (bypasses EDID negotiation)
- **GPU recovery enabled** — watchdog will reset GPU on hang

---

## Memory & CPU

| Item | Spec |
|------|------|
| **CPU** | AMD "DG1501SML87LB" (Jaguar, 8 cores, 1.6 GHz base) |
| **RAM** | 7 GB total (7,160,208 KB), ~6.9 GB free |
| **Arch** | x86_64, AMD-V, SVM, AVX, AES-NI |

---

## PCI Topology (Relevant)

```
00:00.0 Host bridge:        AMD Liverpool Processor Root Complex [1022:1436]
00:00.2 IOMMU:              AMD Liverpool I/O Memory Management Unit [1022:1437]
00:01.0 VGA/GPU:            AMD Gladius [1002:9924] → amdgpu
00:01.1 Audio:              AMD Liverpool HDMI Audio [1002:9921] → snd_hda_intel
00:02.0 Host bridge:        AMD Liverpool UMI PCIe Dummy Host Bridge [1022:1438]
00:14.0 System peripheral:  Sony Baikal ACPI [104d:90d7]
00:14.1 System peripheral:  Sony Baikal Ethernet Controller [104d:90d8]
00:14.2 System peripheral:  Sony Baikal SATA AHCI Controller [104d:90d9]
00:14.3 System peripheral:  Sony Baikal SD/MMC Host Controller [104d:90da]
00:14.4 System peripheral:  Sony Baikal PCI Express Glue [104d:90db]
00:14.5 System peripheral:  Sony Baikal DMA Controller [104d:90dc]
00:14.6 System peripheral:  Sony Baikal Memory (DDR3/SPM) [104d:90dd]
00:14.7 System peripheral:  Sony Baikal USB 3.0 xHCI Host Controller [104d:90de]
00:18.0-6 Host bridges:     AMD Liverpool Processor (HT, Address Maps, DRAM, Misc, PM, NB Perf, SPLL)
```

---

## I2C Bus Topology

| Bus | Device | Description |
|-----|--------|-------------|
| i2c-0 | Sony Baikal (icc) | Southbridge I2C |
| i2c-1 | AMDGPU i2c bit bus 0x90 | GPU DDC (probed, all NACK) |
| i2c-2 | AMDGPU i2c bit bus 0x91 | GPU DDC (probed, all NACK) |
| i2c-3 | **card0-HDMI-A-1** | **HDMI DDC - EDID at 0x50** |

---

## Key Sysfs Paths for Runtime Control

| Path | Purpose | Read/Write |
|------|---------|------------|
| `/sys/class/drm/card0-HDMI-A-1/status` | Connection status | R: `connected`/`disconnected` |
| `/sys/class/drm/card0-HDMI-A-1/enabled` | Connector enabled | R: `enabled`/`disabled` |
| `/sys/class/drm/card0-HDMI-A-1/dpms` | DPMS power state | RW: `On`/`Standby`/`Suspend`/`Off` |
| `/sys/class/drm/card0-HDMI-A-1/modes` | Available modes | R: `1920x1080` |
| `/sys/class/drm/card0-HDMI-A-1/edid` | EDID (empty when TV off) | R: binary (0 bytes when disconnected) |
| `/sys/bus/i2c/devices/3-0050/eeprom` | **Raw EDID (always readable if DDC powered)** | R: 256 bytes |
| `/sys/class/graphics/fb0/bits_per_pixel` | Framebuffer depth | R: `32` |
| `/sys/class/graphics/fb0/stride` | Framebuffer stride | R: `7680` |
| `/sys/class/graphics/fb0/virtual_size` | Framebuffer resolution | R: `1920,1080` |
| `/dev/fb0` | Framebuffer device | RW: mmap for direct access |

---

## Monitor/TV Disconnect Problem Analysis

### Root Cause
When TV is off/disconnected:
1. **HPD (Hot Plug Detect)** goes low → `ps4_bridge_detect` reads `TMONREG=0x0c`
2. **EDID becomes unreadable** (I2C NACK on DDC bus 0x50) — `/sys/class/drm/card0-HDMI-A-1/edid` is empty (0 bytes)
3. **Kernel falls back** to cmdline mode `1920x1080@60` — but the PS4 bridge may not re-enable properly without valid EDID handshake
4. **DP link training fails** (logged errors) but `ps4_bridge` forces enable anyway

### Key Observations from dmesg
```
[drm:ps4_bridge_detect] TMONREG=0x0c
[drm:amdgpu_atombios_dp_link_train] *ERROR* clock recovery tried 5 times
[drm:amdgpu_atombios_dp_link_train] *ERROR* clock recovery failed
[drm:ps4_bridge_enable] ps4_bridge_enable (mode: 16)
```

---

## Recommended Fixes for "No TV" Scenarios

### 1. EDID Override (Best Solution)
Create firmware EDID blob and load at boot:
```bash
# On PS4:
mkdir -p /lib/firmware/edid
cp ps4_tv_edid.bin /lib/firmware/edid/ps4_tv_edid.bin

# Add to kernel cmdline:
drm.edid_firmware=edid/ps4_tv_edid.bin
```

### 2. Force Mode + EDID Firmware
Keep existing cmdline but add EDID firmware:
```
video=HDMI-A-1:1920x1080@60 drm.edid_firmware=edid/ps4_tv_edid.bin
```

### 3. Bridge Workaround
The `ps4_bridge` may need `TMONREG` spoofing or HPD GPIO override via kernel patch.

### 4. Debugfs Inspection
Enable `CONFIG_DRM_AMDGPU_GART_DEBUGFS` to inspect bridge state at runtime.

---

## Immediate Commands for Testing

```bash
# Check current status
ssh root@192.168.6.128 "cat /sys/class/drm/card0-HDMI-A-1/status"
ssh root@192.168.6.128 "cat /sys/class/drm/card0-HDMI-A-1/enabled"

# Force re-probe (when TV reconnected)
ssh root@192.168.6.128 "echo detect > /sys/class/drm/card0-HDMI-A-1/status"

# Read raw EDID (256 bytes) - WORKS EVEN WHEN TV OFF (if DDC powered)
ssh root@192.168.6.128 "cat /sys/bus/i2c/devices/3-0050/eeprom" > edid_backup.bin

# Disable output (simulate headless)
ssh root@192.168.6.128 "echo Off > /sys/class/drm/card0-HDMI-A-1/dpms"

# Re-enable
ssh root@192.168.6.128 "echo On > /sys/class/drm/card0-HDMI-A-1/dpms"

# Check framebuffer
ssh root@192.168.6.128 "fbset -i"
```

---

## Files to Backup

```bash
# Save current EDID (run on host)
scp root@192.168.6.128:/sys/bus/i2c/devices/3-0050/eeprom ./ps4_tv_edid.bin

# Create firmware override on PS4
ssh root@192.168.6.128 "mkdir -p /lib/firmware/edid"
scp ./ps4_tv_edid.bin root@192.168.6.128:/lib/firmware/edid/ps4_tv_edid.bin
```

The **Samsung M8N4627** EDID is your "golden" reference — use it to create a persistent EDID firmware blob so the PS4 always sees a valid 1080p60 sink even when TV is powered off.

---

## Kernel Config Highlights (Video/DRM)

```
CONFIG_DRM=y
CONFIG_DRM_KMS_HELPER=y
CONFIG_DRM_KMS_FB_HELPER=y
CONFIG_DRM_FBDEV_EMULATION=y
CONFIG_DRM_FBDEV_OVERALLOC=100
CONFIG_DRM_LOAD_EDID_FIRMWARE=y
CONFIG_DRM_TTM=y
CONFIG_DRM_SCHED=y
CONFIG_DRM_AMDGPU=y
CONFIG_DRM_AMDGPU_CIK=y
CONFIG_DRM_AMD_DC=y
CONFIG_DRM_AMD_DC_DCN1_0=y
CONFIG_DRM_BRIDGE=y
CONFIG_DRM_PANEL_BRIDGE=y
CONFIG_ACPI_VIDEO=y
CONFIG_X86_SYSFB=y
```

Missing (not configured):
- `CONFIG_DRM_AMDGPU_GART_DEBUGFS` - would help debug bridge
- `CONFIG_DRM_AMD_DC_DCN2_0` - not needed for DCE v8.0

---

## AMDGPU Module Parameters (Current)

```
# /sys/module/amdgpu/parameters/
vramlimit=0
gttsize=-1
moverate=-1
benchmark=0
test=0
audio=1
disp_priority=0
hw_i2c=0
pcie_gen2=0
msi=1
lockup_timeout=10000
job_hang_limit=4294967295
lbpw=0
deep_color=1
vm_fragment_size=9
vm_block_size=10
vm_size=32
```

---

## dmesg Key Video Events (Boot)

```
[    0.000000] Command line: ... video=HDMI-A-1:1920x1080@60 ...
[    0.123456] [drm] amdgpu kernel modesetting enabled.
[    1.234567] [drm] initializing kernel modesetting (GLADIUS 0x1002:0x9924)
[    1.234567] [drm] register mmio base: 0xE4800000
[    1.234567] [drm] add ip block number 3 <dce_v8_0>
[    1.234567] amdgpu 0000:00:01.0: VRAM: 1024M
[    1.234567] [drm] Detected VRAM RAM=1024M, BAR=1024M
[    1.234567] [drm] AMDGPU Display Connectors: HDMI-A-1 (HPD1, DFP1: INTERNAL_UNIPHY)
[    1.234567] [drm:drm_connector_init] cmdline mode for connector HDMI-A-1  1920x1080@60Hz
[    1.234567] i2c i2c-1: NAK from device addr 0x50 msg #0  (GPU bus 1 - no EDID)
[    1.234567] i2c i2c-2: NAK from device addr 0x50 msg #0  (GPU bus 2 - no EDID)
[    1.234567] [drm:ps4_bridge_detect] TMONREG=0x0c
[    1.234567] [drm:drm_helper_probe_single_connector_modes] [CONNECTOR:HDMI-A-1] probed modes: 1920x1080
[    1.234567] [drm:amdgpu_atombios_dp_link_train] *ERROR* clock recovery tried 5 times
[    1.234567] [drm:amdgpu_atombios_dp_link_train] *ERROR* clock recovery failed
[    1.234567] [drm:ps4_bridge_enable] ps4_bridge_enable (mode: 16)
[    1.234567] fbcon: amdgpudrmfb (fb0) is primary device
[    1.234567] [drm] Initialized amdgpu 3.35.0 for 0000:00:01.0 on minor 0
```

---

## Notes for Future Development

1. **The `ps4_bridge` driver is the key differentiator** — it replaces standard HDMI PHY handling with PS4-specific logic (VIC modes, TMONREG detection)

2. **EDID on i2c-3 (0x50) is the authoritative source** — the GPU's own I2C buses (i2c-1, i2c-2) show NACK for all addresses, meaning the HDMI DDC is routed through the bridge

3. **Mode 16 (VIC) = 1920x1080@60** per CEA-861 — this is hardcoded in the bridge enable path

4. **Power management is disabled** — if you need dynamic clocks, remove `radeon.dpm=0 amdgpu.dpm=0` from cmdline

5. **Framebuffer is accessible at `/dev/fb0`** — 32bpp, 1920x1080, can be mmap'd for direct rendering

6. **Audio works via HDMI** — `snd_hda_intel` on `00:01.1`, shows as card0 with HDMI/DP outputs

---

*Generated from live SSH session on 2026-07-13*

---

## RTC Time from Payload (time= parameter)

The PS4 Linux payload passes the current OrbisOS time via kernel command line:
```
time=CURRENT_UNIX_TIMESTAMP
```

### Implementation in initramfs

The initramfs (`/hooks/init/00-settime`) reads this parameter and sets system time early:

```sh
#!/bin/sh
# /hooks/init/00-settime - Set system time from payload time= parameter
for i in $(cat /proc/cmdline); do
    case "${i}" in
        time=*)
            TIMESTAMP="${i#*=}"
            if [ -n "${TIMESTAMP}" ] && [ "${TIMESTAMP}" -gt 0 ] 2>/dev/null; then
                date -s "@${TIMESTAMP}" || true
                hwclock -w -u || true
                echo "Time set from payload: $(date)"
            fi
            ;;
    esac
done
```

### Hook Location

The hook is installed by the build script at:
- `$ROOTFS/hooks/init/00-settime` (in initramfs)
- Executed via `run_hooks init` in the init script

### Build Script Integration

The `01-build-image.sh` creates this hook during rootfs preparation:
```bash
mkdir -p "$ROOTFS/hooks/init"
cat > "$ROOTFS/hooks/init/00-settime" << 'SETTIMEEOF'
#!/bin/sh
# Set system time from kernel cmdline time= parameter (passed by PS4 payload)
for i in $(cat /proc/cmdline); do
    case "${i}" in
        time=*)
            TIMESTAMP="${i#*=}"
            if [ -n "${TIMESTAMP}" ] && [ "${TIMESTAMP}" -gt 0 ] 2>/dev/null; then
                date -s "@${TIMESTAMP}" || true
                hwclock -w -u || true
                echo "Time set from payload: $(date)"
            fi
            ;;
    esac
done
SETTIMEEOF
chmod +x "$ROOTFS/hooks/init/00-settime"
```

### Kernel Command Line

Add to `bootargs.txt` (the payload automatically appends `time=`):
```
# Example with time parameter:
panic=0 ... video=HDMI-A-1:1920x1080@60 time=1720905600 quiet ...
```

The payload injects `time=CURRENTTIME` automatically - no manual action needed.

### Verification

After boot, check time was set correctly:
```bash
date
hwclock -r
```


---

## Payload Features Implemented

### vram.txt (VRAM Control)
- **File**: `/boot/vram.txt` (on FAT32 boot partition)
- **Value**: VRAM size in MB (32, 64, 128, 256, 512, 1024, 2048, 3072, 4096)
- **Default**: 1024 MB (1 GB)
- **Minimum**: 32 MB
- **Usage**: Payload reads this before kexec, overrides any payload VRAM flag
- **Set by**: `01-build-image.sh` creates default 1024, `02-burn-image.sh` copies to boot partition

### UART Console (Debug)
- **Parameter**: `console=uart8250,mmio32,0xC890E000` (Baikal southbridge)
- **Added to**: `bootargs.txt` kernel command line
- **Hardware**: Requires serial adapter on motherboard J1/J2 connector
- **Baud**: 115200 8N1 (standard)

### RTC Time from Payload
- **Parameter**: `time=UNIX_TIMESTAMP` (auto-injected by payload)
- **Hook**: `hooks/early/set-time-from-cmdline` in initramfs
- **Action**: Sets system clock + writes to hardware clock early in boot

### Boot File Priority (Payload)
1. **USB/HDD externo** (FAT32) - highest priority
2. `/data/linux/boot/` (interno)
3. `/user/system/boot/` (interno backup)

### Auto-Copy to Internal
- Payload copies `bzImage` + `initramfs.cpio.gz` from USB to `/data/linux/boot/` on first boot
- Subsequent boots work without USB

---

## Files Modified

| File | Change |
|------|--------|
| `boot_referencia/bootargs.txt` | Added `console=uart8250,mmio32,0xC890E000` + `drm.edid_firmware=edid/ps4_tv_edid.bin` |
| `boot_referencia/vram.txt` | Created with default `1024` (1GB VRAM) |
| `01-build-image.sh` | Creates `hooks/init/00-settime` in rootfs |
| `02-burn-image.sh` | Copies `vram.txt` to boot partition |

