# Levantamento Técnico Profundo — Hardware PS4 "Baikal"

**Data:** 2026-11-12  
**Console:** PlayStation 4 (Sony Interactive Entertainment)  
**Kernel em execução:** `7.0.8-Strawberry-ThinLTO-Baikal-+` (x86_64, clang 19.1.7, ThinLTO)  
**Uptime:** ~3h 50m  
**Temperatura CPU:** 54.2°C (crit 100°C) | **Fan:** 0 RPM  

---

## 1. Visão Geral do Sistema

| Item | Valor |
|------|-------|
| Fabricante | Sony Interactive Entertainment Inc. |
| SoC | AMD Liverpool (Family 22h, Model 67h, Step 0) |
| Microcode | 0x7043001 |
| BIOS/Firmware | Sony, 22/09/2021 (custom Linux bootloader) |
| Memória RAM | 7,06 GiB total (~6,73 GiB disponível) |
| Swap | Desabilitado (0 B); zswap habilitado via cmdline; zram presente sem swap |
| Armazenamento primário | SSD Kingston 120 GB (via USB 3.0 JMicron JMS578) — `/dev/sdb2` = `/` |
| Armazenamento secundário | HDD Toshiba 1 TB MQ04ABF100 (SATA interno) — `/dev/sda` |
| Rede principal | WiFi `wlan0` (192.168.6.128/24) |
| Rede secundária | `eth0` GBE Baikal — DOWN (sem carrier, PHY não acorda) |
| Display | HDMI-A-1 1920×1080@60 (amdgpu, Gladius) |

---

## 2. CPU — AMD Jaguar (DG1501SML87LB)

| Item | Valor |
|------|-------|
| Arquitetura | x86_64 (AMD64), Jaguar |
| Família/Modelo/Stepping | 22 / 67 / 0 |
| Cores/Threads | 8 cores / 8 threads (1 thread/core, sem SMT) |
| Soquetes | 1 (monosocket) |
| L1d | 32 KiB × 8 = 256 KiB total |
| L1i | 32 KiB × 8 = 256 KiB total |
| L2 | 2 MiB × 2 instâncias = 4 MiB total (compartilhado entre pares de cores) |
| L3 | Ausente |
| Endereçamento físico/virtual | 40 bits / 48 bits |
| BogoMIPS | ~3.188 por core (~25.504 total) |
| Frequência observada | ~2.09 GHz (inxi) |
| Virtualização | AMD-V (SVM) disponível |
| Clocksource | TSC (constant_tsc, nonstop_tsc) |
| Mitigações | Desabilitadas (`mitigations=off`) |

### Flags relevantes para desenvolvimento de kernel/driver
`fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx mmxext fxsr_opt pdpe1gb rdtscp lm constant_tsc rep_good nopl nonstop_tsc cpuid extd_apicid aperfmperf pni pclmulqdq monitor ssse3 cx16 sse4_1 sse4_2 movbe popcnt aes xsave avx f16c lahf_lm cmp_legacy svm extapic cr8_legacy abm sse4a misalignsse 3dnowprefetch osvw ibs skinit wdt nodeid_msr topoext perfctr_nb bpext perfctr_llc hw_pstate proc_feedback ssbd vmmcall bmi1 xsaveopt arat npt lbrv svm_lock nrip_save tsc_scale flushbyasid decodeassists pausefilter pfthreshold overflow_recov`

### Vulnerabilidades CPU (mitigations=off)
| Vulnerabilidade | Status |
|-----------------|--------|
| Spectre V1 | VULNERABLE |
| Spectre V2 | VULNERABLE (STIBP disabled) |
| Spec Store Bypass | VULNERABLE |
| Retbleed | VULNERABLE |
| Meltdown / L1TF / MDS / TSX Async Abort | Not affected |

---

## 3. GPU — AMD/ATI Gladius [1002:9924]

| Item | Valor |
|------|-------|
| PCI | 00:01.0 |
| Driver | `amdgpu` (kernel built-in) |
| Framebuffer | `amdgpudrmfb` (/dev/fb0) |
| Arquitetura | GCN-4 (custom PS4 / Liverpool) |
| Conector ativo | HDMI-A-1 |
| Resolução | 1920×1080@60 (modes: 1920p, 720p) |
| Monitor | LG FULL HD (551 mm diagonal, 102 dpi) |
| OpenGL | 4.6 (compat 4.5), mesa radeonsi |
| Vulkan | 1.4.363, mesa radv |
| EGL | 1.5 |
| DPM | Desabilitado (`amdgpu.dpm=0 radeon.dpm=0`) |
| GPU recovery | Habilitado (`amdgpu.gpu_recovery=1`) |
| DRM debug | 0x06 |
| Áudio HDMI | Habilitado (`amdgpu.audio=1`) |
| MMIO VRAM | e0000000 (64M, prefetchable) |
| MMIO GPU | e4000000 (8M, prefetchable) + e4800000 (256K) |
| I/O VGA | 6000 (256 bytes) |
| MSI | 64-bit, EndPoint, MaxPayload 256 bytes |

---

## 4. Áudio — AMD/ATI Liverpool HDMI/DP [1002:9921]

| Item | Valor |
|------|-------|
| PCI | 00:01.1 |
| Driver | `snd_hda_intel` |
| MMIO | e4840000 (64-bit, 16K) |
| IRQ | 43 (PCI-MSI) |
| PCM dispositivos | pcm=3 (event1), pcm=7 (event2) |
| ALSA API | kernel API ativa |

---

## 5. SoC Baikal (Chip Customizado Sony/AMD)

Todos os dispositivos Baikal estão em **IOMMU Group 0** e conectados via PCIe Gen2 x4 (5 GT/s, MaxPayload 128 bytes, MSI 64-bit maskable).

| PCI | Função | Descrição | Driver | MMIO / I/O | Status |
|-----|--------|-----------|--------|------------|--------|
| 00:14.0 | ACPI | Sony Baikal ACPI | — | fdf8000000 (32M), I/O 1000 | Sem driver |
| 00:14.1 | Ethernet | Sony Baikal Ethernet Controller (GBE) | `mts` | c2000000 (4K) | Carregado, **eth0 DOWN** (sem carrier) |
| 00:14.2 | SATA AHCI | Sony Baikal SATA AHCI Controller | `ahci` / `xhci_aeolia` | c4000000 (32K) | Funcional (ata1, ata2) |
| 00:14.3 | SD/MMC | Sony Baikal SD/MMC Host Controller | `sdhci-pci` | c6000000 (4K) | Funcional (mmc0) |
| 00:14.4 | PCIe Glue | Sony Baikal PCI Express Glue | `baikal_pcie` | c8000000 (8K), c8800000 (2M) | Funcional (glue probe OK, chip revision 5c202021:7ca85ea9:0000b100) |
| 00:14.5 | DMA | Sony Baikal DMA Controller | — | ca000000 (4K), ca800000 (4K) | Sem driver |
| 00:14.6 | Memória | Sony Baikal DDR3/SPM | — | cc000000 (4K), 80000000 (1G) | Sem driver |
| 00:14.7 | USB 3.0 | Sony Baikal USB 3.0 xHCI Host Controller | `xhci_aeolia` | ce000000 (4M), cf000000 (8M) | Funcional (4 barramentos USB) |

### MMIO Crítico (endereços físicos)
| Endereço | Tamanho | Descrição |
|----------|---------|-----------|
| 0x80000000–0xBFFFFFFF | 1 GiB | Baikal Memory (SPM/DDR3) |
| 0xC2000000 | 4 KiB | Baikal Ethernet (GBE) |
| 0xC4000000 | 32 KiB | Baikal SATA AHCI |
| 0xC6000000 | 4 KiB | Baikal SD/MMC (mmc0) |
| 0xC8000000–0xC9FFFFFF | 4 MiB | Baikal PCIe Glue (bpcie.glue, bpcie.chipid) |
| 0xCA000000–0xCAFFFFFF | 8 KiB | Baikal DMA |
| 0xCC000000–0xCD43FFFF | ~6,25 MiB | Baikal Memory controller (spm.icc em 0xCD42C000) |
| 0xCE000000–0xCF7FFFFF | 24 MiB | USB xHCI |
| 0xE0000000–0xE4FFFFFF | ~80 MiB | GPU VRAM + MMIO |
| 0xF8000000–0xFBFFFFFF | 64 MiB | PCI MMCONFIG (ECAM) |
| 0xFDF8000000 | 32 MiB | Baikal ACPI |
| 0xFEE00000 | 4 KiB | Local APIC |

---

## 6. Armazenamento

### /dev/sda — Toshiba MQ04ABF100 (HDD interno, 1 TB)
| Item | Valor |
|------|-------|
| Tipo | SATA, rotacional, 5400 rpm, 2.5" |
| Interface | SATA 3.3, 3.0 Gb/s (atual) |
| Capacidade | 1.000.204.886.016 bytes (1 TB) |
| Setores | 1.953.525.168 (512 B logical, 4096 B physical) |
| Firmware | JU0G0A |
| Número de série | X8MNSD6RS |
| SMART | **PASSED** |
| Horas ligado | 4.247 h |
| Contagem de ciclos | 6.036 |
| Setores realocados | 1 (Reallocated_Sector_Ct = 1) |
| Erros logados | Nenhum |
| Particionamento | GPT PS4, 15 partições |
| Partições notáveis | sda13 (12 GiB), sda27 (~897 GiB, principal) |

### /dev/sdb — Kingston SV300S37A120G (SSD 120 GB, via USB 3.0 JMicron JMS578)
| Item | Valor |
|------|-------|
| Tipo | SSD, SandForce driven |
| Interface | SATA 3.0, 6.0 Gb/s (atual), encapsulado em USB 3.0 |
| Capacidade | 120.034.123.776 bytes (120 GB) |
| Firmware | 600ABBF0 |
| Número de série | 50026B724C07B33B |
| SMART | **PASSED** (baseado em atributos) |
| TRIM | Disponível |
| Particionamento | MBR |
| sdb1 | vfat32 BOOT (200 MiB) |
| sdb2 | ext4 `psxitarch` (~111 GiB, 3,4% usado) — **rootfs montado em /** |

---

## 7. Rede

### eth0 — Baikal GBE (00:14.1) — PROBLEMA CONHECIDO
| Item | Valor |
|------|-------|
| Estado | DOWN, NO-CARRIER |
| MAC | 2c:cc:44:3f:69:5f |
| Driver | `mts` (módulo kernel custom, 53.2 KiB, carregado) |
| Link | Não estabelecido (PHY não acorda — causa raiz documentada em LICOES_APRENDIDAS.md) |
| Estatísticas | 0 bytes tx/rx, 0 erros |
| ethtool | Sem dados disponíveis (driver custom não expõe via ethtool) |
| netconsole | Configurado via cmdline (UDP 6665/6666) mas inoperante sem eth0 |

### wlan0 — WiFi (funcional)
| Item | Valor |
|------|-------|
| Estado | UP |
| IP | 192.168.6.128/24 |
| MAC | 00:0c:43:26:60:48 |
| Driver | Não identificado pelo inxi (firmware wireless) |
| Estatísticas | ~1,8 GB rx, ~823 MB tx |

### Interfaces virtuais
- `ap0`, `ap1`: DOWN (no-carrier)
- `tunl0`: DOWN (ipip)

---

## 8. USB — Baikal xHCI Aeolia (00:14.7)

4 barramentos USB registrados (bus 1-4). Controlador xHCI com suporte SuperSpeed.

| Dispositivo | Barramento | Porta | Velocidade | Descrição |
|-------------|-----------|-------|------------|-----------|
| Logitech Keyboard K120 | USB 1 | 1-2 | Low-speed (1,5 Mbps) | Teclado + multimídia (event3, event4) |
| Sony 4-Port USB 2.0 Hub | USB 1 | 1-2.2 | High-speed | Hub interno |
| Sony 4-Port USB 3.0 Hub | USB 2 | 2-2 | SuperSpeed | Hub interno |
| JMicron JMS578 SATA 6Gb/s | USB 2 | 2-2.2 | SuperSpeed | Ponte SATA→USB (conecta SSD sdb) |

---

## 9. Sensores e Power Management

| Sensor | Valor | Limite |
|--------|-------|--------|
| k10temp (CPU die) | 54.2°C | high 70.0°C, crit 100.0°C |
| ps4_fan (ISA) temp1 | 54.0°C | crit 83.0°C |
| ps4_fan fan1 | 0 RPM | — |
| fam15h_power | N/A | crit 0.0 W |

Drivers de plataforma PS4 carregados:
- `ps4-led` — LED driver pronto
- `ps4-fan` — hwmon com temp1_input, temp1_crit, fan1_input
- `ps4-buzzer` — buzzer pronto

---

## 10. Interrupções (IRQ)

| IRQ | CPU | Dispositivo | Tipo |
|-----|-----|-------------|------|
| 1 | CPU0 | AMD-Vi (IOMMU) | PCI-MSI |
| 5 | CPU1 | ICC (Inter-Chip Communication) | IR-Baikal-MSI |
| 34 | CPU2-3 | xhci-hcd:usb1 | IR-Baikal-MSI |
| 35 | CPU2-3 | xhci_aeolia | IR-Baikal-MSI |
| 36 | CPU4 | xhci-hcd:usb3 | IR-Baikal-MSI |
| 42 | CPU5 | mmc0 (SD card) | IR-Baikal-MSI |
| 43 | CPU6 | snd_hda_intel:card0 (HDMI Audio) | PCI-MSI |
| 44 | CPU7 | amdgpu (GPU) | PCI-MSI |

Nota: IRQ 34/35 compartilham CPU2/3. IRQ 42 (mmc0) é a mais ativa.

---

## 11. Kernel e Módulos

| Item | Valor |
|------|-------|
| Versão | 7.0.8-Strawberry-ThinLTO-Baikal-+ |
| Compilador | Debian clang 19.1.7, LLD 19.1.7 |
| Build | root@adsv2, Thu Nov 12 07:18:53 -03 2026 |
| Config | Custom (distro/00-build-kernel-7.0.sh) |
| CONFIG_CIFS | `=m` (módulo, carregado) |
| CONFIG_CIFS_XATTR | `=y` |
| CONFIG_CIFS_POSIX | `=y` |
| CONFIG_MODVERSIONS | Não setado |
| CONFIG_MODULE_SIG | Não setado |
| CONFIG_DEBUG_INFO_BTF | Não setado (desabilitado — boa prática) |
| Módulos carregados | `cifs` (618 KiB), `netfs` (57 KiB), `cifs_md4` (12 KiB), `nls_ucs2_utils` (8 KiB), `mts` (53 KiB) |

### Kernel cmdline
```
panic=0 clocksource=tsc consoleblank=0 net.ifnames=0 radeon.dpm=0 amdgpu.dpm=0
drm.debug=0x06 earlycon=uart8250,mmio32,0xC890E000 console=uart8250,mmio32,0xC890E000
console=tty0 keep_bootcon earlyprintk=efi,keep loglevel=8 root=LABEL=psxitarch rw
rootwait systemd.unified_cgroup_hierarchy=0 systemd.legacy_systemd_cgroup_controller=yes
audit=0 amdgpu.audio=1 usbcore.autosuspend=-1 video=HDMI-A-1:1920x1080@60
mitigations=off zswap.enabled=1 log_buf_len=4M libata.force=1.00:3.0Gbps,noncq
ahci.mobile_lpm_policy=1 netconsole=@192.168.0.2/eth0,6666@192.168.0.1/ff:ff:ff:ff:ff:ff
```

---

## 12. Mounts Ativos

| Ponto de montagem | Fonte | Tipo | Opções relevantes |
|-------------------|-------|------|-------------------|
| `/` | /dev/sdb2 | ext4 | rw,relatime |
| `/mnt/hdauxiliar` | //192.168.6.101/dados_aux | cifs | credentials=/etc/samba/credentials, uid=1001, gid=1001, forceuid/forcegid, vers=3.0, file_mode=0644, dir_mode=0755, _netdev, nofail, x-systemd.automount |
| `/mnt/cifs-test` | //192.168.6.101/dados_aux | cifs | guest, uid=1001, gid=1001, ... (ponto de teste, não persistente) |

---

## 13. Estado dos Drivers e Problemas Conhecidos

### Funcionando
- **amdgpu (Gladius GPU)**: vídeo 1080p@60, OpenGL 4.6, Vulkan 1.4, áudio HDMI
- **xhci_aeolia (USB 3.0)**: 4 barramentos, teclado, hubs, ponte SATA-USB
- **ahci / xhci_aeolia (SATA)**: ata1 (HDD interno 3,0 Gbps UDMA/100), ata2 (ATAPI PS-SYSTEM 1,5 Gbps)
- **sdhci-pci (SD/MMC)**: mmc0 funcional
- **baikal_pcie (PCIe Glue)**: probe OK, chip revision lido
- **ps4-led/fan/buzzer**: drivers de plataforma funcionais
- **cifs**: montagem leitura/escrita funcional (com autenticação Samba real)
- **wlan0**: WiFi funcional, conectado à rede

### Não funcional / Problemas conhecidos
1. **eth0 GBE Baikal (00:14.1)** — DOWN, sem carrier. Driver `mts` carregado mas PHY não acorda. Causa raiz: PHY em power-down separado do MAC; necessário reabilitar IRQ real (IMR não-zero) e sequência de power-on do PHY via ICC/Syscon. Documentado em `LICOES_APRENDIDAS.md` e `kernel/drivers_mts/ICC_GBE_TEST_LOG.md`.
2. **Swap** — desabilitado; apenas zram presente sem swap configurado.
3. **Sem drivers para**: Baikal ACPI (00:14.0), Baikal DMA (00:14.5), Baikal Memory (00:14.6).
4. **console=uart8250** no cmdline conflita com vídeo HDMI (lição #18) — ativo mas sem cabo serial ligado.

---

## 14. Documentação de Hardware Existente no Repositório

| Arquivo | Conteúdo |
|---------|----------|
| `outros/docs/LEVANTAMENTO_HARDWARE_PS4_BAIKAL.md` | Este documento |
| `outros/rea/scans/hardware_report.txt` | Relatório técnico completo anterior (kernel 5.4 neocine) |
| `outros/rea/scans/kernel_hardware_info.txt` | Strings de kernel relacionadas a ICC/GBE |
| `outros/rea/scans/hardware_search_results.txt` | Busca por strings gbe/icc em binários do sistema PS4 |
| `outros/rea/scans/glue_140000_180000_raw.txt` | Dump raw do glue block |
| `outros/rea/scans/glue_140000_180000_analise.txt` | Análise do glue block |
| `outros/rea/decompiled/baikal_pcie_attach*.txt` | Reversão do attach PCIe Baikal |
| `outros/rea/decompiled/baikal_glue_block_reset_dc6df.txt` | Reversão do reset do glue block |
| `outros/rea/decompiled/baikal_sata_phy_init_dc72bfb0.txt` | Reversão da init PHY SATA |
| `outros/rea/decompiled/icc_power_dc528760.txt` | Reversão do power management ICC |
| `kernel/drivers_mts/ICC_GBE_TEST_LOG.md` | Log de testes do driver GBE/mts |
| `kernel/drivers_mts/PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md` | Plano para GBE eth0 |
| `kernel/drivers_mts/MTS_INIT_SEQUENCE_dc5a31f0.md` | Sequência de init do MTS |
| `kernel/MARCO_HISTORICO_GPU_GLADIUS_REAL.md` | Histórico da GPU Gladius |
| `kernel/BAIKAL_DEVLOG.md` | Diário de desenvolvimento Baikal |

---

## 15. Recomendações para Próximos Passos

1. **GBE eth0**: continuar a investigação de power-on do PHY via ICC (Major 4, Minor 0x01 = hard reset do Syscon já mapeado). Ver `PLANO_GBE_ETH0_CONSOLIDADO_2026-07-30.md` e `ICC_GBE_TEST_LOG.md`.
2. **Swap**: considerar ativar swap em partição ou arquivo para evitar OOM em builds de kernel (pico de 11 GB de RSS no pahole já observado).
3. **Drivers Baikal ausentes**: considerar escrever drivers para ACPI (00:14.0), DMA (00:14.5) e Memory (00:14.6) se necessário para controle de power/thermal.
4. **Console UART**: `console=uart8250` conflita com vídeo HDMI — usar apenas para debug headless isolado (sem `video=` no cmdline).
5. **CIFS**: totalmente funcional com autenticação Samba real (opção b). Escrita sem `sudo` confirmada em `/mnt/hdauxiliar/downloads` (755).
