# PS4 Linux Baikal — v1.0.0

Primeira versão de distribuição consolidada do projeto (vivendo em `distro/RELEASE/v1.0.0/`).

> **Status de preservação (2026-11-11):** estes 4 arquivos são hoje a **única cópia íntegra** dessa
> tag — o `distro/boot_referencia/` original não existe mais. O snapshot de 2026-08-01 que servia
> de conferência (MD5 byte a byte) foi apagado em 2026-11-11, então esta pasta é hoje a única
> fonte dessa tag.

## Origem

- Tag de build: `20260801-kvm-rtc-sata-final`
- Kernel: `7.0.8-Strawberry-ThinLTO-Baikal-+ #3` (ThinLTO, profile General, Baikal)
- Commit do repo principal no momento do build: `e40154e` (fix RTC idempotência)
- Artefatos originais ficavam em `distros/arch_minimal_v2/boot_referencia/*-20260801-kvm-rtc-sata-final*`
  (path extinto; **não apagar** os arquivos desta pasta — hoje são a fonte de verdade, cópias
  renomeadas daqueles originais)

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
| **SATA interno (`ata1`, HD real)** | ⚠️ mecanismo de polling 1 ms na função PCI correta (`.7`/xhci-aeolia) validado ao vivo na tag `20260730-sata-polling-fase-ab`; **nesta build o patch foi reconstruído e compilado, mas não há boot de validação registrado** (`test_history` não tem entrada para esta tag) — confirmar em `dmesg` antes de tratar como comprovado |
| **RTC via ICC** | ⚠️ funcional **manualmente** (`date -s` + `hwclock -w` funcionam, relógio avança certo em tempo real) — **não persiste sozinho entre boots**, reinicia em epoch 0 a cada boot. Fix real (MMIO físico) pausado: endereços caem em `System RAM` ativa, risco não assumido. Ver `../../outros/consolidado/BACKLOG.md` (item RTC) |
| **KVM-AMD** | ✅ `/dev/kvm` acessível, `ioctl(KVM_GET_API_VERSION)=12`, nested virt/paging confirmados via `dmesg`, `qemu-system-x86_64` presente no rootfs |

## Deploy

O nome dos arquivos aqui **não segue** o padrão `<TAG>` que `deploy-boot-7.0.sh` espera
automaticamente. Duas opções:

1. **Copiar de volta para `distro/boot_referencia/` com o nome de tag original** e rodar o script oficial:
   ```bash
   T=20260801-kvm-rtc-sata-final
   BR=../distro/boot_referencia && mkdir -p $BR
   cp v1.0.0/bzImage-7.0-v1.0.0            $BR/bzImage-7.0-$T
   cp v1.0.0/config-7.0-v1.0.0             $BR/config-7.0-$T
   cp v1.0.0/bootargs-7.0-v1.0.0.txt       $BR/bootargs-7.0-$T.txt
   cp v1.0.0/initramfs-7.0-v1.0.0.cpio.gz  $BR/initramfs-7.0-$T.cpio.gz
   cd .. && sudo ./deploy-boot-7.0.sh $T
   ```
2. **Copiar manualmente** para a partição BOOT do HD (`psxitarch`), montada em ex. `/mnt/ps4_boot`:
   ```bash
   sudo cp distro/RELEASE/v1.0.0/bzImage-7.0-v1.0.0        /mnt/ps4_boot/bzImage
   sudo cp distro/RELEASE/v1.0.0/bootargs-7.0-v1.0.0.txt   /mnt/ps4_boot/bootargs.txt
   sudo cp distro/RELEASE/v1.0.0/initramfs-7.0-v1.0.0.cpio.gz /mnt/ps4_boot/initramfs.cpio.gz
   ```
   Conferir MD5 depois de copiar, igual a todo deploy do projeto (ver `../../AGENTS.md`).

`config-7.0-v1.0.0` é só referência/histórico (não é copiado pro HD, serve para rebuilds futuros
saberem exatamente qual `.config` gerou este kernel).
