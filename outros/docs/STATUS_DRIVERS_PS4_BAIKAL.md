# Status de Drivers e Componentes — PS4 Baikal

**Data:** 2026-11-15 (atualizado após testes ao vivo na tag `20261113-full-rebuild`)  
**Kernel:** 7.0.8-Strawberry-ThinLTO-Baikal-+ (x86_64)  
**Fonte:** levantamento ao vivo (`lspci`, `lsusb`, `lsmod`, `dmesg`, `inxi`, `lshw`, `smartctl`, `sensors`, testes funcionais)

---

## ✅ Funcionais (driver carregado e operando)

| Componente | Driver | Status | Detalhes |
|------------|--------|--------|----------|
| GPU Gladius [1002:9924] | `amdgpu` | Funcional + aceleração | Vídeo 1080p@60, OpenGL 4.6 (radeonsi), Vulkan 1.4 (radv), DRM/KMS ativo, áudio HDMI |
| WiFi wlan0 | (wireless) | Funcional | UP, 192.168.6.128/24 |
| USB 3.0 Baikal xHCI [00:14.7] | `xhci_aeolia` | Funcional | 4 barramentos, teclado Logitech, hubs Sony, ponte JMicron SATA→USB |
| SATA interno [00:14.2] | `ahci` / `xhci_aeolia` | **Funcional ✅** | ata1: HDD Toshiba 1TB @3.0 Gbps UDMA/100; ata2: ATAPI PS-SYSTEM @1.5 Gbps. **Zero `disable device`, `dd` 27 MB/s** |
| SD/MMC [00:14.3] | `sdhci-pci` | Funcional | mmc0 ativo |
| PCIe Glue Baikal [00:14.4] | `baikal_pcie` | Funcional | Probe OK, chip revision lido |
| Platforma PS4 (LED/Fan/Buzzer) | `ps4-led`, `ps4-fan`, `ps4-buzzer` | Funcional | Sensores de temp/fan, LED, buzzer |
| Áudio HDMI [00:01.1] | `snd_hda_intel` | **Funcional ✅** | `plughw:0,3` (HDMI 0) e `plughw:0,7` (HDMI 1) confirmados com `speaker-test`/`aplay` |
| Baikal Memory [00:14.6] | `baikal-memory` | **Funcional (device) ⚠️ sysfs** | Driver v0.2 in-tree: `/dev/baikal-memory` expõe BARs, MAC `2c:cc:44:3f:69:5f` em offset 0x52f000, ICC em 0x52c000. **Sysfs offsets desalinhados** (device file ≠ atributos `bar5_0x2f000`/`bar5_0x2c000`) |
| RTC via ICC | `rtc-ps4-icc` | **Funcional (timekeeping) ⚠️ hwclock** | `/dev/rtc0` operacional, system clock semeado no boot, `pacman -Sy` OK. `hwclock -r` timeout (falta UIE emulation) |
| CIFS (rede /mnt/hdauxiliar) | `cifs` | **⚠️ Parcial** | cifs.ko no rootfs tem BTF mismatch; autofs configurado. Precisa rebuild módulo contra kernel atual. |
| Baikal DMA [00:14.5] | `baikal-dmac` + `virt-dma` (módulos) | **⚠️ Parcial** | Driver `dmaengine` v0.1 validado (`dmatest` 3000/0). **Módulos no rootfs têm BTF mismatch** — carregar à mão com `insmod`. Ver `BACKLOG.md` |
| Bluetooth | `btmtksdio` (MediaTek MT7668, SDIO) | Funcional | **Teste do usuário em 2026-11-13: funcionando perfeitamente.** Detalhes técnicos no `BACKLOG.md` (item Bluetooth) |
| Áudio via Bluetooth | `btmtksdio` + áudio do sistema | Funcional | **Teste do usuário em 2026-11-13:** reprodução em caixa de som Bluetooth, funcionando perfeitamente |
| Joystick | — | Funcional | **Teste do usuário em 2026-11-13:** funcionando perfeitamente. Modelo e forma de conexão não registrados |

---

## ❌ Não funcionais / sem driver

| Componente | Status | Problema |
|------------|--------|----------|
| Ethernet GBE eth0 [00:14.1] | `mts` carregado, **NO-CARRIER** | MAC `2c:cc:44:3f:69:5f` correto, TX pronto, **PHY não linka** — power-on do PHY feito por firmware Sony antes do kernel; bloqueador de firmware, não solucionável via driver. RE concluída 2026-07-30. |
| Baikal ACPI [00:14.0] | Sem driver | MMIO mapeado, nenhum driver carregado |

---

## ⚠️ Parcial / com ressalvas

| Componente | Detalhe |
|------------|---------|
| **Swap** | zram0 3.4 GiB ativo (zstd) ✅ — configurado via `zram-generator` no build. zswap desabilitado. |
| **console=uart8250** | Ativo no cmdline, conflita com vídeo HDMI (lição #18). Só usável para debug headless isolado, sem `video=`. |
| **netconsole** | Configurado no cmdline, inoperante sem `eth0` funcional. |
| **Módulos no rootfs (BTF mismatch)** | `mts.ko`, `cifs.ko`, `baikal-dmac.ko`, `baikal_wdt.ko`, `baikal-hpet.ko`, `rtc-ps4-icc.ko` no rootfs têm BTF do build anterior e falham ao carregar. Fix: rebuild módulos no `01-build-image-7.0.sh`. |
| **Baikal Memory sysfs** | Offsets no device file (`0x52f000` MAC, `0x52c000` ICC) divergem dos atributos sysfs (`bar5_0x2f000`, `bar5_0x2c000`). Corrigir driver. |
| **RTC UIE emulation** | `hwclock -r` timeout — driver `rtc-ps4-icc` não implementa UIE emulation. `CONFIG_RTC_INTF_DEV_UIE_EMUL=y` já no kernel. |

---

## Resumo

- **Com aceleração de GPU:** sim (`amdgpu`, OpenGL 4.6, Vulkan 1.4).
- **Bluetooth, áudio via Bluetooth e joystick:** sim (teste do usuário em 2026-11-13, funcionando perfeitamente).
- **SATA interno:** ✅ funcional pela primeira vez (UDMA/100, zero `disable device`).
- **Áudio HDMI:** ✅ funcional (HDMI 0 e HDMI 1).
- **RTC via ICC:** ✅ timekeeping funcional; `hwclock -r` timeout (falta UIE).
- **Baikal Memory:** ✅ device funcional; sysfs offsets desalinhados.
- **CIFS / DMA / WDT / HPET:** ⚠️ módulos no rootfs com BTF mismatch — precisam rebuild.
- **Ethernet GBE:** driver funcional, MAC correto, **PHY não linka** (bloqueador firmware).
- **Nem tudo tem driver:** Baikal ACPI sem driver (provavelmente não necessário).
- **Itens a corrigir no próximo build:** BTF mismatch módulos, sysfs offsets Baikal Memory, RTC UIE, alsa-utils no PKGS, S5 power-off, Mesa patchado.
