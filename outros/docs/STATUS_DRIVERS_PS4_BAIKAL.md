# Status de Drivers e Componentes — PS4 Baikal

**Data:** 2026-11-12  
**Kernel:** 7.0.8-Strawberry-ThinLTO-Baikal-+ (x86_64)  
**Fonte:** levantamento ao vivo (`lspci`, `lsusb`, `lsmod`, `dmesg`, `inxi`, `lshw`, `smartctl`, `sensors`)

---

## ✅ Funcionais (driver carregado e operando)

| Componente | Driver | Status | Detalhes |
|------------|--------|--------|----------|
| GPU Gladius [1002:9924] | `amdgpu` | Funcional + aceleração | Vídeo 1080p@60, OpenGL 4.6 (radeonsi), Vulkan 1.4 (radv), DRM/KMS ativo, áudio HDMI |
| WiFi wlan0 | (wireless) | Funcional | UP, 192.168.6.128/24 |
| USB 3.0 Baikal xHCI [00:14.7] | `xhci_aeolia` | Funcional | 4 barramentos, teclado Logitech, hubs Sony, ponte JMicron SATA→USB |
| SATA interno [00:14.2] | `ahci` / `xhci_aeolia` | Funcional | ata1: HDD Toshiba 1TB @3.0 Gbps UDMA/100; ata2: ATAPI PS-SYSTEM @1.5 Gbps |
| SD/MMC [00:14.3] | `sdhci-pci` | Funcional | mmc0 ativo |
| PCIe Glue Baikal [00:14.4] | `baikal_pcie` | Funcional | Probe OK, chip revision lido |
| Platforma PS4 (LED/Fan/Buzzer) | `ps4-led`, `ps4-fan`, `ps4-buzzer` | Funcional | Sensores de temp/fan, LED, buzzer |
| Áudio HDMI [00:01.1] | `snd_hda_intel` | Driver carregado | Carregado, IRQ 43; saída de áudio não testada |
| Baikal Memory [00:14.6] | `baikal-memory` | Funcional | Driver v0.2 in-tree: expõe `/dev/baikal-memory` (0600) e sysfs, leitura de MAC/ICC, escrita controlada na janela BAR2 (DDR3) |
| RTC via ICC | `rtc-ps4-icc` | Funcional | `/dev/rtc0` operacional, sincronização automática com relógio do sistema e NTP (`timedatectl`), fim do bug de 1970 |
| CIFS (rede /mnt/hdauxiliar) | `cifs` | Funcional | Mount leitura/escrita com credenciais Samba, escrita sem sudo em dirs 755 |
| Baikal DMA [00:14.5] | `baikal-dmac` + `virt-dma` (módulos) | Funcional (2026-11-13) | Driver `dmaengine` v0.1, 2 canais, memcpy. `dmatest`: 3000 testes, 0 falhas, inclusive os dois canais ao mesmo tempo. DMAC2 por polling (sem IRQ). **Módulos ainda não persistem no rootfs:** carregar à mão com `insmod`. Ver `BACKLOG.md` |
| Bluetooth | `btmtksdio` (MediaTek MT7668, SDIO) | Funcional | **Teste do usuário em 2026-11-13: funcionando perfeitamente.** Detalhes técnicos no `BACKLOG.md` (item Bluetooth) |
| Áudio via Bluetooth | `btmtksdio` + áudio do sistema | Funcional | **Teste do usuário em 2026-11-13:** reprodução em caixa de som Bluetooth, funcionando perfeitamente |
| Joystick | — | Funcional | **Teste do usuário em 2026-11-13:** funcionando perfeitamente. Modelo e forma de conexão não registrados |

---

## ❌ Não funcionais / sem driver

| Componente | Status | Problema |
|------------|--------|----------|
| Ethernet GBE eth0 [00:14.1] | `mts` carregado, **DOWN** | Sem carrier. PHY não acorda — causa raiz conhecida (PHY em power-down separado do MAC; requer sequência via ICC/Syscon). Documentado em `LICOES_APRENDIDAS.md` e `kernel/drivers_mts/ICC_GBE_TEST_LOG.md`. |
| Baikal ACPI [00:14.0] | Sem driver | MMIO mapeado, nenhum driver carregado |

---

## ⚠️ Parcial / com ressalvas

| Componente | Detalhe |
|------------|---------|
| Swap | Desabilitado (0 B). `zram` presente mas sem swap configurado. Risco de OOM em builds pesados de kernel (pico de 11 GB de RSS no `pahole` já observado). |
| console=uart8250 | Ativo no cmdline, conflita com vídeo HDMI (lição #18). Só usável para debug headless isolado, sem `video=`. |
| netconsole | Configurado no cmdline, inoperante sem `eth0` funcional. |

---

## Resumo

- **Com aceleração de GPU:** sim (`amdgpu`, OpenGL 4.6, Vulkan 1.4).
- **Bluetooth, áudio via Bluetooth e joystick:** sim (teste do usuário em 2026-11-13, funcionando perfeitamente). A linha antiga "Bluetooth não detectado" (levantamento de 2026-11-12) estava desatualizada. Provavelmente porque o MT7668 é um dispositivo SDIO (`mmc0`), que `lspci`/`lsusb` não listam; não verifiquei essa causa.
- **Nem tudo tem driver:** falta driver para o Baikal ACPI (a avaliação é que talvez nem seja necessário); o DMA (`baikal-dmac`) e o Memory (`baikal-memory`) já têm; o GBE tem driver mas não estabelece link.
- **Itens funcionais:** ver a tabela acima (a contagem anterior, "9 de 14", já não batia com a tabela e foi removida).
