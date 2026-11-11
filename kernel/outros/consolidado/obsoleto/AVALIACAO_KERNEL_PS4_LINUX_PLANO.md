# Avaliação Profunda do Kernel PS4 (OrbisOS 12.52) vs Hardware PS4
# Plano de Remoção de Funcionalidades Desnecessárias para Linux no PS4

---

## 1. RESUMO EXECUTIVO

**O que temos:** Dump completo do kernel **OrbisOS 12.52 (FreeBSD 12-based)** - 32.2 MB (ELF 64-bit, x86-64, entry point `0xffffffffdc3ba410`).

**O que NÃO é:** Não é um kernel Linux. É o kernel proprietário da Sony (FreeBSD modificado) rodando no hardware PS4.

**Nosso objetivo:** Criar um kernel **Linux minimalista** (mainline ou 5.4/6.x LTS) que rode no hardware PS4 nu ("bare metal"), substituindo completamente o OrbisOS.

---

## 2. HARDWARE PS4 (CONFIRMADO PELO DUMP + DOCS PÚBLICAS)

| Componente | Especificação | Evidência no Dump |
|------------|---------------|-------------------|
| **CPU** | AMD Jaguar (Family 16h), 8 cores (2 módulos × 4 cores), 1.6 GHz | `FreeBSD/SMP: Multiprocessor System Detected: 8 CPUs`, `MCA: Vendor "AuthenticAMD"`, strings AES-NI/SSSE3 |
| **GPU** | AMD GCN 1.1 (Liverpool), 18 CUs (1152 shaders), 800 MHz, unified GDDR5 | `gc` module (gc.c, vm.c, cail.c), `amdgpu` references, `vce`/`uvd` modules |
| **Memória** | 8 GB GDDR5 unificada (CPU+GPU), 176 GB/s | `add_gpu_dmem is called on a unified memory machine`, `vm_gpu_map_create` |
| **Southbridge** | AMD "Baikal" (custom) | `baikal_pcie.c`, `Orbis Belize/Baikal sata0/sata1` |
| **SATA** | AHCI 1.3 (SATA 3Gbps) - drive interno + HDD externo | `ahci.c`, `ata-ahci`, `SATA 3Gb/s` strings |
| **USB** | xHCI 1.0 (USB 3.0) + EHCI/OHCI (USB 2.0) | `xhci.c`, `usb_controller.c` |
| **Ethernet** | Marvell 88E1116 (GbE) via Baikal PCIe (sky2 driver) | `Marvell 88E1116 Gigabit PHY`, `if_msk.c` (Marvell Yukon) |
| **WiFi/BT** | MediaTek MT7668 (PCIe) - "Torus"/"Trooper" | `if_trsw.c`, `mtwl_core.c`, `torus.c` |
| **Áudio** | HDMI Audio (GPU) + HDA Controller | `hdac.c`, `snd_hda`, `amdgpu.audio=1` |
| **Storage extra** | SDHCI (SD card), SPI Flash (NOR/NAND) | `sdhci.c`, `sflash.c`, `spi` |
| **Segurança** | SBL (Secure Boot Loader), CCP (Cryptographic Coprocessor), RNG, eFuse | `sbl/*`, `ccp_*`, `rng_drv.c`, `eekc_mgr.c` |
| **Power/Term** | SC ESB (I2C/SMBus), ICC (thermal/fan), RTC | `icc_thermal.c`, `emc_timer_*`, `rtc.c` |
| **Display** | HDMI 1.4/2.0 via DCE (display controller) | `hdmi.c`, `crtc.c`, `flip.c`, `dce.c` |

**Resumo:** Hardware **fixo, conhecido, sem variações** (diferente de PC). Não há enumeração de hardware genérico - tudo é estático.

---

## 3. O QUE O KERNEL ORBISOS TEM (E NÃO PRECISAMOS NO LINUX)

### 3.1 Subsistemas Sony-Proprietários (REMOVER 100%)

| Subsistema | Arquivos no Dump | Função | Ação no Linux |
|------------|------------------|--------|---------------|
| **SBL (Secure Boot Loader)** | `sbl/authmgr/*`, `sbl/service/*`, `sbl/devact/*`, `sbl/driver/*`, `sbl/idata/*`, `sbl/lvp_config/*`, `sbl/npdrm/*`, `sbl/pltauth/*`, `sbl/pup_update/*`, `sbl/qafutkn/*`, `sbl/rng/*`, `sbl/sm_service/*`, `sbl/srtc/*`, `sbl/usb_dongle/*`, `sbl/vtrm/*`, `sbl/zlib/*` | Boot seguro, verificação de assinatura, DRM, updates, chaves, relógio seguro | **REMOVER TUDO** - Linux usa seu próprio bootloader (kexec/efistub) |
| **SC ESB (System Control Embedded Subsystem)** | `scesb/dmac/*`, `scesb/emc_timer/*`, `scesb/icc/*`, `scesb/rtc/*`, `scesb/sbram/*`, `scesb/sflash/*`, `scesb/twsi/*` | Gerenciamento de energia, thermal, fan, RTC, SPI flash, I2C | **SUBSTITUIR** por drivers Linux padrão (`hwmon`, `thermal`, `rtc`, `spi`, `i2c`) |
| **Orbis Kernel Modules** | `orbis_budget.c`, `orbis_cpumode.c`, `orbis_evf.c`, `orbis_gnt.c`, `orbis_idt.c`, `orbis_mdbg.c`, `orbis_notification.c`, `orbis_pmc.c`, `orbis_sem.c`, `orbis_swd.c` | Orçamento CPU, power management, eventos, grant tables, debug, notificações | **REMOVER** - Linux tem `cpufreq`, `pm_runtime`, `eventfd`, `grant_table` (Xen), `printk` |
| **GC (Graphics Command) / GPU Driver Sony** | `gc/cail.c`, `gc/dump.c`, `gc/gbase_ioctl.c`, `gc/gc.c`, `gc/gc_suspend_resume.c`, `gc/gc_watchdog.c`, `gc/memory_pstate.c`, `gc/samu.c`, `gc/vm.c`, `gc/vmid0_va_allocator.c` | Driver GPU proprietário, command submission, VM, SAMU | **SUBSTITUIR** por `amdgpu` (mainline) |
| **DCE / HDMI / Display** | `dce/*`, `hdmi/hdmi.c`, `crtc.c`, `flip.c`, `ih.c`, `scanin.c` | Display controller, HDMI, interrupts | **SUBSTITUIR** por `amdgpu` + `drm` + `drm_kms_helper` |
| **VCE / UVD (Video Encode/Decode)** | `uvd/kmd/*`, `vce/kmd_os_wrapper.c`, `vce/sce_gpkmd.c` | Video encode/decode HW | **MANTER** via `amdgpu` (já suporta UVD/VCE/Vcn) |
| **Audio (HDA/PCM)** | `audioout/snd_hda/*`, `audioout/sound/pcm/*`, `audioout/uaudio/*` | HD Audio, PCM, USB Audio | **SUBSTITUIR** por `snd_hda_intel` + `snd_hda_codec_hdmi` + `snd_usb_audio` |
| **Bluetooth HID** | `bluetooth_hid/*`, `bt/bt_driver.c`, `bt/bt_gatt.c`, `bt/bt_sys.c` | Bluetooth HID, GATT | **SUBSTITUIR** por `btusb` + `bluez` (userspace) |
| **WLAN (Torus/Trooper)** | `wlan/torus/*`, `wlan/trooper/*` | Driver WiFi MediaTek MT7668 | **SUBSTITUIR** por `mt76` (mainline) |
| **Screenshot / Sdma** | `screenshot/*`, `sdma/*` | Captura de tela, SDMA engine | **REMOVER** - userspace faz isso via DRM/KMS |
| **Camera / HMD / HMDDFU** | `camera/*`, `hmd/*`, `hmddfu/*` | PS Camera, PSVR | **REMOVER** (exceto se for suportar PSVR no Linux) |
| **IPMI / Regmgr / Mbus / Mas** | `ipmimgr/*`, `regmgr/*`, `mbus/*`, `mas/*` | Gestão de sistema, registry, message bus | **REMOVER** - Linux usa `systemd`, `dbus`, `kmsg` |
| **DECI (Debug/DevKit)** | `devenv/deci_daemon/*`, `workbench/nanobug/*`, `workbench/metaDebugger/*` | Debug remoto, coredump, live debug | **REMOVER** - Linux usa `gdb`, `kdump`, `netconsole`, `serial` |

---

### 3.2 FreeBSD Genérico que NÃO se aplica ao PS4 (REMOVER)

| Subsistema | Motivo |
|------------|--------|
| **ACPI completo** (`acpi_*`, `acpi_perf.c`, `acpi_cpu.c`, `acpi_thermal.c`, `acpi_battery.c`, `acpi_lid.c`, `acpi_pcib.c`, `acpi_pci_link.c`, `acpi_powerres.c`, `acpi_smbat.c`, `acpi_ec.c`, `acpi_acad.c`) | PS4 **não tem ACPI** (não é PC). Tables ACPI são mínimas/falsas. Linux no PS4 usa **Device Tree (DT)** ou **hardcoded** |
| **PCI/PCIe genérico** (`pci_cfgreg.c`, `pci.c`, `baikal_pcie.c`) | Topologia PCIe fixa. Não há hotplug, não há enumeração dinâmica. `amdgpu` e drivers sabem exatamente onde estão |
| **USB genérico completo** (`usb/*`, `xhci.c`, `uhci/ohci/ehci` não vistos) | Apenas xHCI 1.0. Não há hubs internos complexos. Drivers USB storage/hid genéricos OK |
| **SATA/AHCI genérico** (`ahci.c`, `ata-all.c`, `ata-queue.c`, `scsi_*`) | OK manter base, mas apenas 1 porta SATA interna + 1 externa. Sem RAID, sem multiplos HBA |
| **Networking stack completo** (`net/*`, `netinet/*`, `netinet6/*`, `bpf.c`, `if_*`, `vlan`, `pppoe`, `raw_cb.c`) | **MANTER** stack TCP/IP (Linux tem o seu). Remover: `bpf` (não usado), `pppoe`, `vlan` (a menos que precise), `raw_ip` (pode manter mínimo) |
| **Filesystems** (`cd9660`, `udf2`, `exfat`, `ffs/ufs`, `unionfs`, `nullfs`, `tmpfs`, `procfs`, `pseudofs`, `mlfs`, `pfs/*`) | **MANTER**: ext4, f2fs, vfat (EFI), tmpfs, procfs, sysfs. **REMOVER**: ufs, ffs, cd9660, udf2, exfat (exceto se precisar ler disco PS4), unionfs, pfs |
| **CAM/SCSI** (`cam/*`, `scsi_*`) | Apenas para BD drive (SCSI) e HDD (AHCI/ATA). Manter `scsi_mod` + `sd_mod` + `sr_mod` mínimo |
| **Crypto/Random** (`random/*`, `yarrow.c`) | Linux usa `getrandom`/`urandom` + `crng`. RNG HW via CCP (se exposto) |
| **Audit/BSM** (`security/audit/*`) | Não necessário. Linux usa `auditd` opcional |
| **KLD/Kernel Modules (link_elf*)** | Linux usa `kmod` (`.ko`), formato diferente |
| **Jails/Containers** (`kern_jail.c`, `kern_umtx.c`) | Linux usa `cgroups` + `namespaces` (já no kernel) |
| **POSIX Timers/RT** (`p1003_1b.c`, `sched_rt.c`) | Linux tem `timerfd`, `timer_create`, `sched_deadline` |
| **KTR/KTrace** (`kern_ktrace.c`) | Linux usa `ftrace`, `perf`, `tracepoints` |
| **DTrace/SDT** | Não portado. Linux usa `tracepoints` + `bpf` |
| **GEOM** (`geom/*`) | Linux usa `blk-mq` + `device-mapper` + `dm-*` |
| **VFS específico FreeBSD** (`vfs_aio*`, `vfs_bio.c`, `vfs_cluster.c`, `vfs_export.c`, `vfs_hash.c`, `vfs_lookup.c`, `vfs_mountroot.c`, `vfs_subr.c`, `vfs_syscalls.c`, `vfs_vnops.c`) | Linux VFS é diferente. Manter conceitos, código é outro |
| **UMA/Slab** (`uma_core.c`, `vm_*`) | Linux usa `slab`/`slub`/`slob` |
| **PMAP/VM Machdep** (`pmap.c`, `vm_machdep.c`, `vm_mmap.c`, `vm_object.c`, `vm_page*`, `vm_phys.c`, `vm_pager*`) | Linux MM é diferente (page tables 4-level, folio, etc) |

---

## 4. FEATURES LINUX DESNECESSÁRIAS NO PS4 (PLANO DE REMOÇÃO)

### 4.1 **TIER 1: REMOÇÃO ABSOLUTA (Zero impacto, economiza RAM/tamanho/build time)**

| CONFIG | Descrição | Economia Estimada | Justificativa PS4 |
|--------|-----------|-------------------|-------------------|
| `CONFIG_DEBUG_INFO_BTF` | BTF (BPF Type Format) para CO-RE | **~11 GB RAM no build**, +tempo link, ~MB no vmlinux | **JÁ DOCUMENTADO EM LICOES_APRENDIDAS.md**. Não usamos bpftrace/BCC/libbpf. Debug é via `dmesg`/telnet/MMIO. `CONFIG_BPF_SYSCALL=y` continua funcionando sem BTF |
| `CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT` | DWARF debug info | ~50-100 MB no vmlinux | Strip no deploy. Manter apenas `CONFIG_DEBUG_INFO=y` se precisar `kgdb` |
| `CONFIG_KALLSYMS_ALL` | Todos símbolos no kallsyms | ~2-5 MB | `CONFIG_KALLSYMS=y` basta para `dmesg`/stack trace |
| `CONFIG_PRINTK_CALLBACK` | Callback de printk | Pequeno | Não usado |
| `CONFIG_DEBUG_KERNEL` | Muitas checks de debug | Variável | Desabilitar em produção. Manter `CONFIG_DEBUG_MISC=y` mínimo |

### **TIER 2: ARQUITETURAS E PLATAFORMAS NÃO-PS4 (Economia de código morto)**

| CONFIG | Por que remover |
|--------|-----------------|
| `CONFIG_X86_32` | PS4 é x86-64 only |
| `CONFIG_X86_BIG_SMP` | 8 cores não precisa "big SMP" (>8 sockets) |
| `CONFIG_X86_ESRT` | EFI System Resource Table - não usado |
| `CONFIG_EFI` / `CONFIG_EFI_STUB` / `CONFIG_EFI_MIXED` | PS4 não boot via UEFI. Usamos kexec/payload |
| `CONFIG_ACPI` **COMPLETO** | **CRÍTICO**: PS4 não tem ACPI real. Substituir por Device Tree (`CONFIG_OF=y` + `CONFIG_OF_FLATTREE=y` + DT hardcoded) |
| `CONFIG_PCI_QUIRKS` | Quirks para hardware PC genérico. PS4 não precisa |
| `CONFIG_PCI_IOV` / `CONFIG_PCI_PRI` / `CONFIG_PCI_PASID` / `CONFIG_PCI_LABEL` | SR-IOV, PASID, PRI - virtualização PCIe. Não aplicável |
| `CONFIG_HOTPLUG_PCI` / `CONFIG_HOTPLUG_PCI_PCIE` | Sem hotplug no PS4 |
| `CONFIG_PCIEASPM` | ASPM power management PCIe. Hardware fixo |
| `CONFIG_INTEL_IOMMU` / `CONFIG_AMD_IOMMU` | IOMMU (VT-d/AMD-Vi). PS4 usa IOMMU custom (baikal_pcie). `amd_iommu` do Linux pode conflitar. **Testar se amdgpu precisa**. Provavelmente `CONFIG_AMD_IOMMU=y` mas sem `CONFIG_AMD_IOMMU_V2` |
| `CONFIG_SWIOTLB` | Software I/O TLB para DMA. PS4 tem memória unificada, não precisa |
| `CONFIG_X86_VSYSCALL_EMULATION` | vsyscall legacy. Não usado em 64-bit moderno |
| `CONFIG_LEGACY_VSYSCALL_NONE` | OK manter |
| `CONFIG_IA32_EMULATION` / `CONFIG_X86_32` | 32-bit userspace. **Manter se quiser rodar binários 32-bit (wine/steam)**, senão remover |
| `CONFIG_COMPAT_32BIT_TIME` | time_t 32-bit compat. Verificar necessidade |

### **TIER 3: DRIVERS DE HARDWARE INEXISTENTE NO PS4**

#### **CPU / SoC**
| CONFIG | Driver | Status PS4 |
|--------|--------|------------|
| `CONFIG_X86_INTEL_LPSS` | Intel Low Power Subsystem | ❌ AMD |
| `CONFIG_X86_AMD_PLATFORM_DEVICE` | AMD platform device | ⚠️ Verificar se `amdgpu` precisa |
| `CONFIG_CPU_IDLE` | CPU idle states | ⚠️ Jaguar tem C-states? Provavelmente não expostos |
| `CONFIG_CPU_FREQ` / `CONFIG_CPU_FREQ_GOV_*` | CPUFreq | ⚠️ Jaguar 1.6GHz fixo. `CONFIG_CPU_FREQ` pode ser n |
| `CONFIG_X86_ACPI_CPUFREQ` | ACPI cpufreq | ❌ Sem ACPI |
| `CONFIG_PROCESSOR_MAX` / `CONFIG_NR_CPUS` | **Ajustar para 8** (não 256/4096 default) | ✅ `NR_CPUS=8` economiza percpu |

#### **Barramento / Interconnect**
| CONFIG | Driver | Status PS4 |
|--------|--------|------------|
| `CONFIG_PCI_MSI` | MSI/MSI-X | ✅ GPU usa MSI. Manter |
| `CONFIG_PCI_ECAM` | ECAM config space | ❌ PS4 usa MMIO custom (baikal_pcie) |
| `CONFIG_PCI_MSI_IRQ_DOMAIN` | MSI irq domain | ✅ Necessário para MSI |
| `CONFIG_PCIEPORTBUS` | PCIe port bus | ❌ Não há portas PCIe expostas |
| `CONFIG_PCIEAER` / `CONFIG_PCIE_ECRC` | AER/ECRC | ❌ Sem RAS |
| `CONFIG_PCI_IOAPIC` | PCI IOAPIC | ❌ APIC é local APIC/x2APIC only |

#### **I/O - Storage**
| CONFIG | Driver | Status PS4 |
|--------|--------|------------|
| `CONFIG_SATA_AHCI` | AHCI | ✅ **MANTER** (HDD interno + externo) |
| `CONFIG_AHCI_SUNXI` / `CONFIG_SATA_INIC162X` / etc | Vendor-specific | ❌ Remover todos exceto genérico |
| `CONFIG_PATA_*` | PATA/IDE | ❌ Remover todos |
| `CONFIG_SCSI_LOWLEVEL` | HBAs SCSI | ❌ Remover todos (megaraid, mpt3sas, qla2xxx, lpfc, etc) |
| `CONFIG_NVME_CORE` / `CONFIG_BLK_DEV_NVME` | NVMe | ❌ PS4 não tem NVMe |
| `CONFIG_MMC` / `CONFIG_MMC_SDHCI` | SD/eMMC | ⚠️ **MANTER** `sdhci` (slot SD card existe) |
| `CONFIG_SPI_MASTER` / `CONFIG_SPI_FLASH` | SPI NOR/NAND | ⚠️ **MANTER** mínimo (bootloader, firmware) |

#### **I/O - USB**
| CONFIG | Driver | Status PS4 |
|--------|--------|------------|
| `CONFIG_USB_XHCI_HCD` | xHCI 1.0 | ✅ **MANTER** (portas frontais) |
| `CONFIG_USB_EHCI_HCD` / `CONFIG_USB_OHCI_HCD` / `CONFIG_USB_UHCI_HCD` | USB 2.0/1.1 HC | ❌ Remover (só xHCI) |
| `CONFIG_USB_STORAGE` | USB Mass Storage | ✅ **MANTER** (HDD externo, pendrive) |
| `CONFIG_USB_HID` | HID (teclado/mouse) | ✅ **MANTER** |
| `CONFIG_USB_SERIAL` / `CONFIG_USB_ACM` / etc | Serial USB | ⚠️ Manter mínimo para debug (`usb_serial`, `cp210x`, `ftdi_sio`, `pl2303`) |

#### **I/O - Rede**
| CONFIG | Driver | Status PS4 |
|--------|--------|------------|
| `CONFIG_SKY2` | Marvell Yukon 2 (88E1116/88E8055) | ✅ **MANTER** (Ethernet GBE) |
| `CONFIG_MT76_CORE` / `CONFIG_MT76_PCI` / `CONFIG_MT76x2U` | MediaTek MT7668 | ✅ **MANTER** (WiFi/BT) |
| `CONFIG_BRCMFMAC` / `CONFIG_ATH9K` / `CONFIG_IWLWIFI` / `CONFIG_RTW88` / etc | Outros WiFi | ❌ Remover TODOS |
| `CONFIG_BT` / `CONFIG_BT_HCIBTUSB` / `CONFIG_BT_INTEL` / `CONFIG_BT_BCM` | Bluetooth | ⚠️ **MANTER** `btusb` + `btbcm` (MT7668 tem BT) |

#### **GPU / Display / Media**
| CONFIG | Driver | Status PS4 |
|--------|--------|------------|
| `CONFIG_DRM_AMDGPU` | amdgpu | ✅ **MANTER** (OBRIGATÓRIO) |
| `CONFIG_DRM_AMDGPU_SI` | Southern Islands (GCN 1.0) | ❌ PS4 é GCN 1.1 (CIK) |
| `CONFIG_DRM_AMDGPU_CIK` | Sea Islands (GCN 1.1) | ✅ **MANTER** (Liverpool = CIK) |
| `CONFIG_DRM_AMDGPU_USERPTR` | Userptr | ✅ Manter para compute |
| `CONFIG_DRM_AMDGPU_GART_DEBUGFS` | DebugFS GART | ❌ Remover debug |
| `CONFIG_DRM_AMD_DC` / `CONFIG_DRM_AMD_DC_DCN*` | Display Core (DCN) | ❌ **REMOVER** - PS4 usa DCE antigo, não DCN. `amdgpu` tem `CONFIG_DRM_AMD_DC` mas para PS4 precisa path DCE |
| `CONFIG_DRM_AMDGPU_CIK_HDMI` | HDMI CIK | ✅ **MANTER** |
| `CONFIG_DRM_AMDGPU_VCE` / `CONFIG_DRM_AMDGPU_UVD` | VCE/UVD | ✅ **MANTER** (video encode/decode) |
| `CONFIG_DRM_RADEON` | radeon (legacy) | ❌ **REMOVER** - obsoleto |
| `CONFIG_DRM_I915` / `CONFIG_DRM_NOUVEAU` / `CONFIG_DRM_VMWGFX` / etc | Intel/Nvidia/VMware | ❌ Remover TODOS |
| `CONFIG_DRM_PANEL` / `CONFIG_DRM_BRIDGE` / `CONFIG_DRM_PANEL_ORIENTATION_QUIRKS` | Panels/bridges genéricos | ❌ PS4 não tem panel interno. HDMI só |
| `CONFIG_HDMI` / `CONFIG_HDMI_CEC` | HDMI/CEC core | ⚠️ `amdgpu` já inclui HDMI. `CEC` não necessário |

#### **Áudio**
| CONFIG | Driver | Status PS4 |
|--------|--------|------------|
| `CONFIG_SND_HDA_INTEL` | HDA Controller | ✅ **MANTER** |
| `CONFIG_SND_HDA_CODEC_HDMI` | HDMI Audio Codec | ✅ **MANTER** (áudio via HDMI) |
| `CONFIG_SND_HDA_CODEC_REALTEK` / `CONFIG_SND_HDA_CODEC_ANALOG` / etc | Codecs analógicos | ❌ Remover |
| `CONFIG_SND_USB_AUDIO` | USB Audio | ⚠️ Manter para headsets USB |
| `CONFIG_SND_SOC` / `CONFIG_SND_SOC_*` | ASoC (ARM/SoC audio) | ❌ Remover tudo |

#### **Sensores / Thermal / HWMon**
| CONFIG | Driver | Status PS4 |
|--------|--------|------------|
| `CONFIG_HWMON` / `CONFIG_SENSORS_*` | lm-sensors | ⚠️ **MANTER** `k10temp` (CPU temp AMD), `amdgpu` expõe GPU temp |
| `CONFIG_THERMAL` / `CONFIG_THERMAL_OF` / `CONFIG_CPU_THERMAL` | Thermal framework | ✅ **MANTER** (fan control crítico) |
| `CONFIG_PWM` / `CONFIG_PWM_FAN` | PWM Fan | ✅ **MANTER** (controlar fan via ICC/SCESB) |
| `CONFIG_HW_RANDOM_AMD` | AMD RNG (RDRAND) | ✅ **MANTER** |

#### **Input / HID**
| CONFIG | Driver | Status PS4 |
|--------|--------|------------|
| `CONFIG_INPUT_EVDEV` | evdev | ✅ **MANTER** |
| `CONFIG_HID_GENERIC` / `CONFIG_HID` | HID core | ✅ **MANTER** |
| `CONFIG_HID_SONY` / `CONFIG_HID_PLAYSTATION` | DS4/DS5 | ✅ **MANTER** (controle via USB/BT) |
| `CONFIG_INPUT_JOYDEV` | joydev | ✅ **MANTER** (retroarch/steam) |
| `CONFIG_INPUT_MOUSEDEV` / `CONFIG_INPUT_KEYBOARD` / etc | mouse/keyboard legacy | ⚠️ Manter mínimo |

#### **Virtualização / Sandbox**
| CONFIG | Status PS4 |
|--------|------------|
| `CONFIG_KVM` / `CONFIG_KVM_AMD` | ❌ PS4 não tem virtualização HW (SVM não exposto). Remover |
| `CONFIG_VHOST` / `CONFIG_VHOST_NET` / `CONFIG_VHOST_VSOCK` | ❌ Remover |
| `CONFIG_NET_9P` / `CONFIG_9P_FS` | ❌ Remover (virtio/9p) |
| `CONFIG_VIRTIO` / `CONFIG_VIRTIO_PCI` / `CONFIG_VIRTIO_MMIO` | ❌ Remover |

#### **Filesystems (Manter apenas o essencial)**
| Manter | Remover |
|--------|---------|
| `ext4`, `f2fs` (rootfs), `vfat` (EFI/boot), `tmpfs`, `procfs`, `sysfs`, `devtmpfs`, `cgroupfs`, `pstore`, `efivarfs` | `btrfs`, `xfs`, `jfs`, `reiserfs`, `ufs`, `ffs`, `nilfs2`, `ocfs2`, `gfs2`, `ceph`, `cifs`, `nfs`, `fuse` (manter se precisar), `overlayfs` (manter para containers), `squashfs` (initramfs), `erofs` |

#### **Crypto / Security**
| Manter | Remover |
|--------|---------|
| `CONFIG_CRYPTO_AES_NI_INTEL` (AES-NI funciona em AMD), `CONFIG_CRYPTO_SHA*_SSSE3`, `CONFIG_CRYPTO_GHASH_CLMUL_NI_INTEL`, `CONFIG_CRYPTO_DEV_SP_PSP` (PSP/SEV - não no PS4) | `CONFIG_CRYPTO_DEV_CCP` (CCP é do PS4 mas driver Linux é diferente), `CONFIG_CRYPTO_DEV_QAT`, `CONFIG_CRYPTO_DEV_VIRTIO` |
| `CONFIG_SECURITY_SELINUX` / `CONFIG_SECURITY_APPARMOR` | ❌ Remover (overhead). `CONFIG_SECURITY_YAMA=y` mínimo |
| `CONFIG_INTEGRITY` / `CONFIG_IMA` / `CONFIG_EVM` | ❌ Remover |

#### **Debug / Tracing (Manter mínimo para debug remoto)**
| Manter | Remover |
|--------|---------|
| `CONFIG_PRINTK`, `CONFIG_DYNAMIC_DEBUG`, `CONFIG_DEBUG_FS`, `CONFIG_MAGIC_SYSRQ`, `CONFIG_SERIAL_8250` / `CONFIG_SERIAL_8250_CONSOLE` (UART debug), `CONFIG_NETCONSOLE`, `CONFIG_KGDB` / `CONFIG_KGDB_SERIAL_CONSOLE` | `CONFIG_FTRACE` (pesado), `CONFIG_PERF_EVENTS` (pesado), `CONFIG_KPROBES` / `CONFIG_KRETPROBES`, `CONFIG_UPROBES`, `CONFIG_BPF_KPROBE_OVERRIDE`, `CONFIG_DEBUG_KMEMLEAK`, `CONFIG_DEBUG_OBJECTS`, `CONFIG_DEBUG_VM`, `CONFIG_DEBUG_LIST`, `CONFIG_DEBUG_SG`, `CONFIG_DEBUG_NOTIFIERS`, `CONFIG_DEBUG_CREDENTIALS`, `CONFIG_DEBUG_FORCE_WEAK_PER_CPU`, `CONFIG_DEBUG_PER_CPU_MAPS`, `CONFIG_DEBUG_HIGHMEM` |

---

### **TIER 4: OTIMIZAÇÕES DE TAMANHO/MEMÓRIA (build config)**

| CONFIG | Valor Recomendado PS4 | Justificativa |
|--------|----------------------|---------------|
| `CONFIG_NR_CPUS` | **8** | Default 256/4096 gasta percpu memory |
| `CONFIG_MAX_PHYSMEM_BITS` | **36** (64GB) ou **39** (512GB) | PS4 tem 8GB. 36 bits = 64GB suficiente. Default 46/52 gasta page tables |
| `CONFIG_KEXEC` | **y** | Necessário para boot Linux via payload |
| `CONFIG_KEXEC_FILE` | **y** | kexec file-based |
| `CONFIG_CRASH_DUMP` | **n** | Não temos kdump storage |
| `CONFIG_PROC_VMCORE` | **n** | Sem kdump |
| `CONFIG_SLAB` | **y** (SLUB default) | SLUB OK. `CONFIG_SLUB_DEBUG=n` |
| `CONFIG_MODULES` | **y** | Manter módulos para drivers opcionais |
| `CONFIG_MODULE_UNLOAD` | **y** | Permitir unload |
| `CONFIG_MODVERSIONS` | **n** | Não necessário, economiza espaço |
| `CONFIG_TRIM_UNUSED_KSYMS` | **y** | Remove symbols não exportados |
| `CONFIG_STRIP_ASM_SYMS` | **y** | Strip asm symbols |
| `CONFIG_DEBUG_INFO` | **n** (produção) / **y** (debug) | Em produção: `n` |
| `CONFIG_DEBUG_INFO_BTF` | **n** | **JÁ DOCUMENTADO - REMOVER** |
| `CONFIG_DEBUG_INFO_DWARF5` | **n** | |
| `CONFIG_DEBUG_INFO_COMPRESSED` | **y** (se debug) | |
| `CONFIG_HAVE_DEBUG_KMEMLEAK` | **n** | |
| `CONFIG_KALLSYMS` | **y** | Para dmesg/stack trace |
| `CONFIG_KALLSYMS_ALL` | **n** | |
| `CONFIG_BPF` / `CONFIG_BPF_SYSCALL` | **y** | Manter syscall (systemd usa), mas sem BTF |
| `CONFIG_BPF_JIT` | **y** | JIT ajuda performance |
| `CONFIG_BPF_JIT_ALWAYS_ON` | **n** | |
| `CONFIG_HAVE_EBPF_JIT` | **y** | |
| `CONFIG_CGROUPS` | **y** | systemd precisa |
| `CONFIG_CGROUP_V1` | **y** | systemd 258 usa v1 |
| `CONFIG_CGROUP_V2` | **n** | Não usado |
| `CONFIG_CPUSETS` | **n** | Não necessário |
| `CONFIG_CGROUP_PIDS` | **y** | systemd usa |
| `CONFIG_CGROUP_FREEZER` | **n** | |
| `CONFIG_CGROUP_DEVICE` | **y** | systemd usa |
| `CONFIG_CGROUP_CPUACCT` | **n** | |
| `CONFIG_CGROUP_PERF` | **n** | |
| `CONFIG_CGROUP_SCHED` | **n** | |
| `CONFIG_CGROUP_BPF` | **n** | |
| `CONFIG_NAMESPACES` | **y** | Containers básicos |
| `CONFIG_UTS_NS` / `CONFIG_IPC_NS` / `CONFIG_PID_NS` / `CONFIG_NET_NS` / `CONFIG_USER_NS` | **y** | Para systemd/docker básico |
| `CONFIG_SCHED_AUTOGROUP` | **n** | Desktop feature, não server |
| `CONFIG_FAIR_GROUP_SCHED` | **n** | |
| `CONFIG_CFS_BANDWIDTH` | **n** | |
| `CONFIG_RT_GROUP_SCHED` | **n** | |
| `CONFIG_CPU_IDLE` | **n** | Jaguar não expõe C-states |
| `CONFIG_CPU_FREQ` | **n** | Clock fixo 1.6GHz |
| `CONFIG_X86_ACPI_CPUFREQ` | **n** | Sem ACPI |
| `CONFIG_X86_POWERNOW_K8` | **n** | Legacy |
| `CONFIG_ACPI_PROCESSOR` | **n** | |
| `CONFIG_ACPI_CPPC_LIB` | **n** | |
| `CONFIG_X86_SPEEDSTEP_LIB` | **n** | |
| `CONFIG_HZ` | **250** ou **1000** | 250 economiza timer interrupts. 1000 para low latency (audio/gaming) |
| `CONFIG_HZ_250` | **y** | Recomendado |
| `CONFIG_NO_HZ_IDLE` | **y** | Tickless idle |
| `CONFIG_NO_HZ_FULL` | **n** | Full tickless complexo, pode quebrar |
| `CONFIG_VIRT_CPU_ACCOUNTING_GEN` | **y** | |
| `CONFIG_TICK_CPU_ACCOUNTING` | **n** | |
| `CONFIG_PREEMPT` | **y** (voluntary) ou **PREEMPT** (full) | `PREEMPT_VOLUNTARY` equilibrado. `PREEMPT` para gaming/low latency |
| `CONFIG_PREEMPT_RT` | **n** | Não é RT kernel |
| `CONFIG_SLAB_MERGE_DEFAULT` | **y** | Merge slabs similares |
| `CONFIG_SLAB_FREELIST_RANDOM` | **n** | Segurança, custa performance |
| `CONFIG_SLAB_FREELIST_HARDENED` | **n** | |
| `CONFIG_SHUFFLE_PAGE_ALLOCATOR` | **n** | |
| `CONFIG_PAGE_POISONING` | **n** | |
| `CONFIG_DEBUG_PAGEALLOC` | **n** | |
| `CONFIG_DEBUG_RODATA` | **n** | |
| `CONFIG_DEBUG_SET_MODULE_RONX` | **n** | |
| `CONFIG_DEBUG_WX` | **n** | |
| `CONFIG_DEBUG_KERNEL` | **n** | Produção |
| `CONFIG_DEBUG_MISC` | **y** | Mínimo |
| `CONFIG_MAGIC_SYSRQ` | **y** | Debug via serial |
| `CONFIG_MAGIC_SYSRQ_SERIAL` | **y** | |
| `CONFIG_DEBUG_STACKOVERFLOW` | **n** | |
| `CONFIG_DEBUG_CREDENTIALS` | **n** | |
| `CONFIG_DEBUG_NOTIFIERS` | **n** | |
| `CONFIG_DEBUG_LIST` | **n** | |
| `CONFIG_DEBUG_SG` | **n** | |
| `CONFIG_DEBUG_VM` | **n** | |
| `CONFIG_DEBUG_VIRTUAL` | **n** | |
| `CONFIG_DEBUG_PER_CPU_MAPS` | **n** | |
| `CONFIG_DEBUG_HIGHMEM` | **n** | |
| `CONFIG_DEBUG_KMEMLEAK` | **n** | |
| `CONFIG_DEBUG_OBJECTS` | **n** | |
| `CONFIG_DEBUG_OBJECTS_FREE` | **n** | |
| `CONFIG_DEBUG_OBJECTS_TIMERS` | **n** | |
| `CONFIG_DEBUG_OBJECTS_WORK` | **n** | |
| `CONFIG_DEBUG_OBJECTS_RCU_HEAD` | **n** | |
| `CONFIG_DEBUG_OBJECTS_PERCPU_COUNTER` | **n** | |
| `CONFIG_DEBUG_OBJECTS_ENABLE_DEFAULT` | **n** | |
| `CONFIG_DEBUG_SLAB` | **n** | |
| `CONFIG_DEBUG_RT_MUTEXES` | **n** | |
| `CONFIG_DEBUG_SPINLOCK` | **n** | |
| `CONFIG_DEBUG_MUTEXES` | **n** | |
| `CONFIG_DEBUG_WW_MUTEX_SLOWPATH` | **n** | |
| `CONFIG_DEBUG_LOCK_ALLOC` | **n** | |
| `CONFIG_DEBUG_LOCKDEP` | **n** | |
| `CONFIG_DEBUG_ATOMIC_SLEEP` | **n** | |
| `CONFIG_DEBUG_SLEEP` | **n** | |
| `CONFIG_DEBUG_SPINLOCK_SLEEP` | **n** | |
| `CONFIG_DEBUG_LOCKING_API_SELFTESTS` | **n** | |
| `CONFIG_LOCK_TORTURE_TEST` | **n** | |
| `CONFIG_WW_MUTEX_SELFTEST` | **n** | |
| `CONFIG_DEBUG_KOBJECT` | **n** | |
| `CONFIG_DEBUG_KOBJECT_RELEASE` | **n** | |
| `CONFIG_DEBUG_BUGVERBOSE` | **n** | |
| `CONFIG_DEBUG_INFO` | **n** (prod) | |
| `CONFIG_DEBUG_INFO_BTF` | **n** | **CRÍTICO** |
| `CONFIG_DEBUG_INFO_DWARF5` | **n** | |
| `CONFIG_DEBUG_INFO_COMPRESSED` | **n** | |
| `CONFIG_GDB_SCRIPTS` | **n** | |
| `CONFIG_FRAME_POINTER` | **y** | Necessário para unwind/stack trace |
| `CONFIG_STACK_VALIDATION` | **y** | Para ORC unwind |
| `CONFIG_UNWINDER_ORC` | **y** | ORC unwinder (menor que DWARF) |
| `CONFIG_UNWINDER_FRAME_POINTER` | **n** | |
| `CONFIG_DEBUG_FORCE_FUNCTION_ALIGN_32B` | **n** | |
| `CONFIG_DEBUG_FORCE_FUNCTION_ALIGN_64B` | **n** | |
| `CONFIG_OPTIMIZE_INLINING` | **y** | |
| `CONFIG_CC_OPTIMIZE_FOR_SIZE` | **y** | Kernel menor (-Os) |
| `CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE` | **n** | |
| `CONFIG_LD_DEAD_CODE_DATA_ELIMINATION` | **y** | LTO + dead code elimination |
| `CONFIG_LTO` | **y** (thin) | ThinLTO economiza espaço |
| `CONFIG_LTO_CLANG` | **n** (se gcc) | |
| `CONFIG_THINLTO` | **y** | |

---

## 5. PLANO DE AÇÃO RECOMENDADO

### Fase 1: Config Base Minimal (Kernel 6.6 LTS ou 6.1 LTS)
```bash
# Base: make defconfig + ajustes PS4
make ARCH=x86_64 defconfig

# Aplicar script de config PS4 (criar scripts/config-ps4.sh)
./scripts/config-ps4.sh
```

### Fase 2: Device Tree / Platform Data
- Criar `arch/x86/boot/dts/sony/ps4.dts` com:
  - CPU: 8 cores, Jaguar, 1.6GHz, L2 2MB×2
  - Memória: 8GB unificada @ 0x0 - 0x200000000
  - GPU: amdgpu @ PCIe 00:01.0 (hardcoded)
  - SATA: AHCI @ PCIe 00:02.0
  - USB: xHCI @ PCIe 00:03.0
  - Ethernet: sky2 @ PCIe 00:04.0
  - WiFi: mt76 @ PCIe 00:05.0
  - Audio: HDA @ GPU (HDMI)
  - UART: 8250 @ MMIO 0xC890E000 (debug)
  - PWM Fan: via SC ESB (I2C)
  - RTC: via SC ESB
  - GPIO: via SC ESB
  - SPI Flash: para bootloader/firmware

### Fase 3: Drivers Críticos (Portar/Ativar)
1. **amdgpu** - CIK support (CONFIG_DRM_AMDGPU_CIK=y)
2. **sky2** - Marvell 88E1116
3. **mt76** - MT7668 (PCIe)
4. **ahci** - SATA
5. **xhci** - USB 3.0
6. **snd_hda_intel + snd_hda_codec_hdmi** - Áudio HDMI
7. **k10temp** - CPU temp
8. **pwm-fan** + driver custom SC ESB para fan control
9. **uart_8250** - Debug serial

### Fase 4: Initramfs Mínimo
- busybox + systemd 258 + dropbear (ssh) + amdgpu firmware + mt76 firmware
- Target: < 15 MB comprimido

### Fase 5: Bootloader / Payload
- kexec via payload (já funcionando: scene-kmem-dumper)
- Carregar kernel + initramfs + dtb + cmdline
- cmdline: `console=ttyS0,115200 console=tty0 root=/dev/sda2 rw rootwait systemd.unified_cgroup_hierarchy=0 amdgpu.audio=1 mitigations=off`

---

## 6. ESTIMATIVA DE ECONOMIA

| Item | Kernel Padrão (defconfig) | Kernel PS4 Mínimo | Economia |
|------|---------------------------|-------------------|----------|
| **vmlinux (unstripped)** | ~150-200 MB | ~30-50 MB | **~70-80%** |
| **bzImage (comprimido)** | ~25-30 MB | ~8-12 MB | **~60%** |
| **Build RAM peak** | ~12-16 GB (com BTF) | ~3-4 GB | **~75%** |
| **Build time** | ~45-60 min | ~15-25 min | **~60%** |
| **Boot time (kernel only)** | ~3-5s | ~1-2s | **~50%** |
| **Runtime RAM (kernel)** | ~200-400 MB | ~50-100 MB | **~70%** |

---

## 7. CONCLUSÃO

O kernel OrbisOS 12.52 dump confirmado (32.2 MB, FreeBSD, build J02690760 de 2016) valida que o hardware PS4 é **estático, conhecido e limitado**. Não há razão para compilar suporte a hardware que não existe.

**Top 3 remoções de maior impacto:**
1. **`CONFIG_DEBUG_INFO_BTF=n`** - Economia imediata de 11 GB RAM no build (já validado)
2. **`CONFIG_ACPI=n` + Device Tree** - Remove milhares de linhas de código morto, evita conflitos
3. **`CONFIG_NR_CPUS=8` + `CONFIG_MAX_PHYSMEM_BITS=36`** - Economia percpu + page tables

**Próximo passo:** Criar `scripts/config-ps4.sh` aplicando todas as configs acima e testar build.

---

*Documento baseado na análise do dump `kmem_dump_1252.bin` (33.7 MB, ELF FreeBSD x86-64) e documentação do projeto em `consolidado/LICOES_APRENDIDAS.md` e `memory/`.*