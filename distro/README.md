# Distro Linux — Baikal (frente 2)

A distribuição **Arch Linux mínima** que roda no PS4 Baikal: geração do rootfs,
initramfs, gravação no HD, deploy do boot, firmware/Mesa patchado, utilitários de
montagem das partições PFS do HD interno e os artefatos de release.

> O kernel que roda **embaixo** desta distro é a frente 1, em [`../kernel/`](../kernel/).

## Dependência explícita da frente 1

Esta frente **não compila kernel**. Ela consome os artefatos por tag de
`../kernel/boot_referencia/`:

```
../kernel/boot_referencia/
├── bzImage-7.0-<TAG>
├── config-7.0-<TAG>
├── bootargs-7.0-<TAG>.txt
└── initramfs-7.0-<TAG>.cpio.gz
```

Todos os scripts usam `BOOT_DIR="${PS4_BOOT_REF:-$SCRIPT_DIR/../kernel/boot_referencia}"`,
então dá para apontar para outro conjunto de artefatos sem editar nada:
`PS4_BOOT_REF=/caminho/para/boot_referencia sudo ./deploy-boot-7.0.sh <TAG>`.

## Pipeline

```bash
cd distro
sudo ./01-build-image-7.0.sh        # rootfs Arch + initramfs  -> ../kernel/boot_referencia/initramfs-7.0-<TAG>.cpio.gz
sudo ./02-burn-image-7.0.sh /dev/sdX # particiona + grava rootfs e boot (label psxitarch)
sudo ./deploy-boot-7.0.sh <TAG>      # só o boot, mantém o rootfs intacto
sudo ./rebuild-initramfs-7.0.sh      # reconstrói initramfs de rootfs já montado
./scripts/promote-release.sh <TAG>   # promove tag testada para RELEASE/
```

## Conteúdo

| Caminho | O que é |
|---|---|
| `01-build-image-7.0.sh` | Gera rootfs Arch (`pkglist.x86_64.txt`), firmware, Mesa patchado, `mts.ko`, scripts de montagem, initramfs |
| `02-burn-image-7.0.sh` | Particiona o HD (`sda1` FAT32 + `sda2` ext4 label **`psxitarch`**) e grava tudo |
| `deploy-boot-7.0.sh` | Reescreve só a partição BOOT a partir dos artefatos da tag (com MD5 origem→destino) |
| `rebuild-initramfs-7.0.sh` | Reconstrói o initramfs num rootfs já montado em `/mnt/ps4_rootfs_7.0` |
| `monta_particao.sh` / `desmonta_particao.sh` / `automount.sh` | Montagem nativa das partições PFS do HD interno (chave EAP + mapper) |
| `ssh-startup.sh` + `ssh-auto-startup.service` | SSH (WiFi) automático no boot |
| `firmware_gpu/`, `firmware_wifi/` | Firmware genuíno (Gladius/amdgpu, MediaTek MT7668) |
| `hardware_ps4_real/` | Coletas de hardware feitas no console real (`/proc`, `lspci`, …) |
| `mesa/` | Patch + build do Mesa que reconhece `CHIP_GLADIUS`/`CHIP_LIVERPOOL` |
| `monitor_edid/` | EDID do monitor e utilitários de vídeo |
| `ps4_tv_edid.bin` | EDID injetado no initramfs (`drm.edid_firmware`) |
| `scripts/` | `promote-release.sh`, `ps4_crypt_mount.sh`, `fetch_gladius_fw.py` |
| `RELEASE/` | Artefatos de distribuição (`v1.0.0` versionado; demais tags são build local) |

## Regras que valem para esta frente

- **Label `psxitarch` é obrigatória** na partição root: o `init` do initramfs faz
  `mount LABEL=psxitarch /newroot` literalmente. Outra label = rescue shell.
- `mkinitcpio.conf` **sempre** `COMPRESSION="gzip"` (o kernel 7.0 Baikal não tem
  `CONFIG_RD_ZSTD`).
- `bootargs` usa UART MMIO (`uart8250,mmio32,0xC890E000`) + `console=tty0` e
  `rootwait` — nunca `console=ttyS0` nem `rootdelay=N`.
- Deploy só com os 4 arquivos da tag presentes, conferindo MD5. Sem fallback
  silencioso para o initramfs genérico.
- Regras completas: [`../AGENTS.md`](../AGENTS.md).
