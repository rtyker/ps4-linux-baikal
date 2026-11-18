# Status de Drivers e Componentes — PS4 Baikal

**Data:** 2026-11-18 (atualizado após a Ethernet validada ao vivo na tag `20261117-mtsx`; base anterior: `20261113-full-rebuild`, 2026-11-15)  
**Kernel:** 7.0.8-Strawberry-ThinLTO-Baikal-+ (x86_64)  
**Fonte:** levantamento ao vivo (`lspci`, `lsusb`, `lsmod`, `dmesg`, `inxi`, `lshw`, `smartctl`, `sensors`, testes funcionais)

---

## ✅ Funcionais (driver carregado e operando)

| Componente | Driver | Status | Detalhes |
|------------|--------|--------|----------|
| GPU Gladius [1002:9924] | `amdgpu` | Funcional + aceleração | Vídeo 1080p@60, OpenGL 4.6 (radeonsi), Vulkan 1.4 (radv), DRM/KMS ativo, áudio HDMI |
| WiFi wlan0 | (wireless) | Funcional | UP, `192.168.6.128/24` (pode ir para `.127` por um lease quando a `eth0` sobe) |
| USB 3.0 Baikal xHCI [00:14.7] | `xhci_aeolia` | Funcional | 4 barramentos, teclado Logitech, hubs Sony, ponte JMicron SATA→USB |
| SATA interno [00:14.2] | `ahci` / `xhci_aeolia` | **Funcional ✅** | ata1: HDD Toshiba 1TB @3.0 Gbps UDMA/100; ata2: ATAPI PS-SYSTEM @1.5 Gbps. **Zero `disable device`, `dd` 27 MB/s** |
| SD/MMC [00:14.3] | `sdhci-pci` | Funcional | mmc0 ativo |
| PCIe Glue Baikal [00:14.4] | `baikal_pcie` | Funcional | Probe OK, chip revision lido |
| Platforma PS4 (LED/Fan/Buzzer) | `ps4-led`, `ps4-fan`, `ps4-buzzer` | Funcional | Sensores de temp/fan, LED, buzzer |
| Áudio HDMI [00:01.1] | `snd_hda_intel` | **Funcional ✅** | `plughw:0,3` (HDMI 0) e `plughw:0,7` (HDMI 1) confirmados com `speaker-test`/`aplay` |
| Baikal Memory [00:14.6] | `baikal-memory` | **Funcional ✅** | Driver v0.2 in-tree: `/dev/baikal-memory` expõe BARs, MAC `2c:cc:44:3f:69:5f` em offset 0x52f000, ICC em 0x52c000. ~~Sysfs offsets desalinhados~~ — **falso alarme, verificado ao vivo em 2026-11-17 (`test_history` 114):** os atributos `bar5_0x2f000`/`bar5_0x2c000` mostram exatamente os mesmos dados do device file |
| RTC via ICC | `rtc-ps4-icc` | **Funcional ✅** | `/dev/rtc0` operacional, system clock semeado no boot, `pacman -Sy` OK. `hwclock -r` **funciona** (validado na tag `20261115-hwclock-min`) |
| CIFS (rede /mnt/hdauxiliar) | `cifs` | **⚠️ Parcial** | cifs.ko instalado pelo `install-modules-7.0.sh`; autofs configurado. O "BTF mismatch" era do build antigo — desde 2026-11-16 o BTF está desligado e os módulos do rootfs foram reinstalados |
| Baikal DMA [00:14.5] | `baikal-dmac` + `virt-dma` (módulos) | **⚠️ Parcial** | Driver `dmaengine` v0.1 validado (`dmatest` 3000/0) e, em 2026-11-16/17, `baikal-memory` por DMA (547–624 MB/s) e swap na SPM. Instalado pelo `install-modules-7.0.sh` (sem BTF). Ver `BACKLOG.md` |
| Bluetooth | `btmtksdio` (MediaTek MT7668, SDIO) | Funcional | **Teste do usuário em 2026-11-13: funcionando perfeitamente.** Detalhes técnicos no `BACKLOG.md` (item Bluetooth) |
| Áudio via Bluetooth | `btmtksdio` + áudio do sistema | Funcional | **Teste do usuário em 2026-11-13:** reprodução em caixa de som Bluetooth, funcionando perfeitamente |
| Joystick | — | Funcional | **Teste do usuário em 2026-11-13:** funcionando perfeitamente. Modelo e forma de conexão não registrados |
| **Ethernet GBE eth0 [00:14.1]** | **`mtsx`** | **Funcional ✅** | Tag `20261117-mtsx`: link up (`BAR0+0x04` `0xb19`, resíduo C45 `0x0147.1e` limpo), MAC `2c:cc:44:3f:69:5f`, **100 MB em cada sentido com SHA-256 idêntico**, 0 erros. IP por **DHCP** (`192.168.6.131`), rota padrão pela cabeada. `CONFIG_MTSX=m` no build, autoload pelo rootfs, `blacklist mts` no legado. Ver `PLAN_ETH0_BAIKAL.md` |

---

## ❌ Não funcionais / sem driver

| Componente | Status | Problema |
|------------|--------|----------|
| Baikal ACPI [00:14.0] | Sem driver | MMIO mapeado, nenhum driver carregado |

> A Ethernet GBE (`eth0`) **saiu desta tabela em 2026-11-17**: está funcional com o `mtsx` (ver a tabela de funcionais e `others/docs/PLAN_ETH0_BAIKAL.md`). A tese anterior de "bloqueador de firmware no power-on do PHY" está **refutada**.

---

## ⚠️ Parcial / com ressalvas

| Componente | Detalhe |
|------------|---------|
| **Swap** | zram0 3.4 GiB ativo (zstd) ✅ — configurado via `zram-generator` no build. zswap desabilitado. |
| **console=uart8250** | Ativo no cmdline, conflita com vídeo HDMI (lição #18). Só usável para debug headless isolado, sem `video=`. |
| **netconsole** | Removido do `bootargs` (não ativa: a `eth0` antiga só nascia aos ~44 s). Com o `mtsx` a interface já está funcional desde cedo, então reativar é possível — falta testar com o driver novo. |
| **Módulos no rootfs (BTF mismatch)** | **OBSOLETO desde 2026-11-16:** o BTF está desligado no kernel e o `install-modules-7.0.sh` faz o strip. Os módulos do rootfs foram reinstalados e conferidos por `srcversion`. |
| ~~**Baikal Memory sysfs**~~ | **Falso alarme (2026-11-17, `test_history` 114):** os atributos sysfs mostram os mesmos dados do device file. Nenhuma correção necessária. |
| ~~**RTC UIE emulation**~~ | **Resolvido:** `hwclock -r` funciona desde a tag `20261115-hwclock-min`. |

---

## Resumo

- **Com aceleração de GPU:** sim (`amdgpu`, OpenGL 4.6, Vulkan 1.4).
- **Bluetooth, áudio via Bluetooth e joystick:** sim (teste do usuário em 2026-11-13, funcionando perfeitamente).
- **SATA interno:** ✅ funcional pela primeira vez (UDMA/100, zero `disable device`).
- **Áudio HDMI:** ✅ funcional (HDMI 0 e HDMI 1).
- **RTC via ICC:** ✅ timekeeping funcional e `hwclock -r` funcionando (tag `20261115-hwclock-min`).
- **Baikal Memory:** ✅ device funcional; os "offsets sysfs desalinhados" eram falso alarme (2026-11-17).
- **CIFS / DMA / WDT / HPET:** ⚠️ o "BTF mismatch" é obsoleto (BTF desligado desde 2026-11-16, módulos reinstalados); `baikal_wdt`/`baikal-hpet` seguem desligados no config.
- **Ethernet GBE (`eth0`):** ✅ **FUNCIONAL** com o `mtsx` — link up, 100 MB em cada sentido com SHA-256 idêntico, IP por DHCP (tag `20261117-mtsx`).
- **Nem tudo tem driver:** Baikal ACPI sem driver (provavelmente não necessário).
- **Itens a corrigir no próximo build:** tirar `mts` do `MODULES` do initramfs, S5 completo (`shutdown -h now`/`reboot` já homologados), Mesa patchado. Os antigos "sysfs offsets" e "RTC UIE" estão resolvidos.
