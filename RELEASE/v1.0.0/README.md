# PS4 Linux Baikal — v1.0.0

Primeira versão de distribuição consolidada do projeto.

## Origem

- Tag de build: `20260801-kvm-rtc-sata-final`
- Kernel: `7.0.8-Strawberry-ThinLTO-Baikal-+ #3` (ThinLTO, profile General, Baikal)
- Commit do repo principal no momento do build: `e40154e` (fix RTC idempotência)
- Artefatos originais em `distros/arch_minimal_v2/boot_referencia/*-20260801-kvm-rtc-sata-final*`
  (**não apagar** — são a fonte de verdade; os arquivos aqui em `RETAIL/` são cópias renomeadas)

## Arquivos

| Arquivo | MD5 |
|---|---|
| `bzImage-7.0-v1.0.0` | `03b41ef53e48c67ffb0670299ad984dc` |
| `config-7.0-v1.0.0` | `2041f0f5015be5c84ebe55c3d10c78a2` |
| `bootargs-7.0-v1.0.0.txt` | `4038399f34266f6b795ae6fb0eb16d31` |
| `initramfs-7.0-v1.0.0.cpio.gz` | `f6e413122f77b0720375ac0c9435fee9` |

## Features confirmadas (validado ao vivo em 2026-08-01)

| Feature | Status |
|---|---|
| Boot completo (kexec → kernel → initramfs → rootfs) | ✅ |
| Vídeo HDMI 1080p60 | ✅ |
| SSH via WiFi (`192.168.6.128`) | ✅ |
| Ethernet `eth0` (`mts.ko`) | ⚠️ MAC/DMA OK, PHY sem link (bug conhecido, não é regressão) |
| **SATA interno (`ata1`, HD real)** | ✅ via polling timer 1ms na função PCI correta (`.7`/xhci-aeolia) — zero timeout/disable device em 1h+ de uptime testado |
| **RTC via ICC** | ⚠️ funcional **manualmente** (`date -s` + `hwclock -w` funcionam, relógio avança certo em tempo real) — **não persiste sozinho entre boots**, reinicia em epoch 0 a cada boot. Fix real (MMIO físico) pausado: endereços caem em `System RAM` ativa, risco não assumido. Ver `memory/rtc-mmio-pausado-risco-system-ram-2026-08-01.md` |
| **KVM-AMD** | ✅ `/dev/kvm` acessível, `ioctl(KVM_GET_API_VERSION)=12`, nested virt/paging confirmados via `dmesg`, `qemu-system-x86_64` presente no rootfs |

## Deploy

O nome dos arquivos aqui **não segue** o padrão `<TAG>` que `deploy-boot-7.0.sh` espera
automaticamente. Duas opções:

1. **Copiar de volta para `boot_referencia/` com o nome de tag original** e rodar o script oficial:
   ```bash
   cd distros/arch_minimal_v2
   sudo ./deploy-boot-7.0.sh 20260801-kvm-rtc-sata-final
   ```
2. **Copiar manualmente** para a partição BOOT do HD (`psxitarch`), montada em ex. `/mnt/ps4_boot`:
   ```bash
   sudo cp RETAIL/bzImage-7.0-v1.0.0        /mnt/ps4_boot/bzImage
   sudo cp RETAIL/bootargs-7.0-v1.0.0.txt   /mnt/ps4_boot/bootargs.txt
   sudo cp RETAIL/initramfs-7.0-v1.0.0.cpio.gz /mnt/ps4_boot/initramfs.cpio.gz
   ```
   Conferir MD5 depois de copiar, igual a todo deploy do projeto (ver `AGENTS.md`).

`config-7.0-v1.0.0` é só referência/histórico (não é copiado pro HD, serve para rebuilds futuros
saberem exatamente qual `.config` gerou este kernel).
