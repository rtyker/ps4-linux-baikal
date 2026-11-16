# Distro Linux — Baikal (frente 2)

A distribuição **Arch Linux mínima** que roda no PS4 Baikal: geração do rootfs,
initramfs, gravação no HD, deploy do boot, firmware/Mesa patchado, utilitários de
montagem das partições PFS do HD interno e os artefatos de release.

> O kernel que roda **embaixo** desta distro é a frente 1, em [`../kernel/`](../kernel/).

## Dependência explícita da frente 1

Esta frente **não compila kernel**. Ela consome os artefatos por tag de
`./boot_referencia/` (dentro de `distro/`):

```
./boot_referencia/
├── bzImage-7.0-<TAG>
├── config-7.0-<TAG>
├── bootargs-7.0-<TAG>.txt
└── initramfs-7.0-<TAG>.cpio.gz
```

Todos os scripts usam `BOOT_DIR="${PS4_BOOT_REF:-$SCRIPT_DIR/boot_referencia}"`,
então dá para apontar para outro conjunto de artefatos sem editar nada:
`PS4_BOOT_REF=/caminho/para/boot_referencia sudo ./deploy-boot-7.0.sh <TAG>`.

## Pipeline

**Tudo é por TAG** — a mesma tag do build do kernel:

```bash
cd distro
sudo ./01-build-image-7.0.sh <TAG>              # rootfs Arch + initramfs -> ./boot_referencia/initramfs-7.0-<TAG>.cpio.gz
sudo ./02-burn-image-7.0.sh /dev/sdX "" <TAG>   # particiona + grava rootfs e boot (label psxitarch)
sudo ./deploy-boot-7.0.sh <TAG>                 # só o boot, mantém o rootfs intacto
sudo ./rebuild-initramfs-7.0.sh <TAG>           # reconstrói initramfs de rootfs já montado
./scripts/promote-release.sh <TAG>              # promove tag testada para RELEASE/
```

Sem TAG, os scripts autodetectam **apenas** se houver exatamente uma tag em
`boot_referencia/` — nunca escolhem no escuro (com várias, abortam listando-as).

## Ambiente de build: host Arch ou container

O `01-build-image-7.0.sh` usa `pacstrap`, `pacman` e `arch-chroot` — ferramentas
**Arch**. Em host Arch, o build é nativo:

```bash
cd distro && sudo ./01-build-image-7.0.sh <TAG>
```

Em host **sem** Arch (Debian/Ubuntu), use o wrapper — ele roda **o mesmo script
oficial** dentro de `archlinux:latest`, com o repositório e a área de build
montados por bind-mount (`--privileged`, porque o `arch-chroot` precisa montar
`/proc`, `/sys`, `/dev`, `/run` dentro do rootfs):

```bash
cd distro && ./scripts/build-image-docker.sh <TAG>
```

### Modo incremental (`--incremental`)

Como a maior parte do desenvolvimento é de kernel/drivers, o rootfs raramente
muda. O `--incremental` pula `rm -rf $BUILD_ROOT` + `pacstrap` e reusa o rootfs
já construído, indo direto para configuração + `mkinitcpio` + tarball:

```bash
./scripts/build-image-docker.sh <TAG> --incremental   # host sem Arch
sudo ./01-build-image-7.0.sh <TAG> --incremental      # host Arch
```

- **Exige** um rootfs válido em `PS4_BUILD_ROOT/rootfs`; se não existir,
  aborta com erro (sem fallback silencioso).
- O primeiro build da máquina é sempre completo: `--incremental` sem rootfs falha.
- Build completo é obrigatório quando muda pacote, `pkglist`, firmware, Mesa,
  hooks do `mkinitcpio` ou qualquer coisa fora do kernel.

### Sentinela de conclusão

Ao terminar com sucesso, o `01-build-image-7.0.sh` cria
`boot_referencia/.build-complete-<TAG>` e imprime `=== BUILD COMPLETO: <TAG> ===`.
O wrapper Docker checa esse arquivo e reporta explicitamente sucesso/falha —
a existência da sentinela é a prova de que o build terminou (não confunda
build travado com build terminado).

Os artefatos saem direto no disco do host (owner root), em
`boot_referencia/`. O cache do pacman fica em
`/mnt/hdauxiliar/temp/pacman-cache` (compartilhado entre builds).

## Conteúdo

| Caminho | O que é |
|---|---|
| `01-build-image-7.0.sh` | Gera rootfs Arch (`pkglist.x86_64.txt`), firmware, Mesa patchado, `mts.ko`, scripts de montagem, initramfs |
| `02-burn-image-7.0.sh` | Particiona o HD (`sda1` FAT32 + `sda2` ext4 label **`psxitarch`**) e grava tudo |
| `deploy-boot-7.0.sh` | Reescreve só a partição BOOT a partir dos artefatos da tag (com MD5 origem→destino) |
| `rebuild-initramfs-7.0.sh` | Reconstrói o initramfs num rootfs já montado em `/mnt/ps4_rootfs_7.0` |
| `monta_particao.sh` / `desmonta_particao.sh` / `desmonta_todas.sh` / `automount.sh` | Montagem nativa das partições do HD interno (UFS2/FAT32, chave EAP + `iv_offset` via `dmsetup`); `automount.sh` monta no boot via `ps4-automount.service`. Chave do usuário em `/etc/ps4-keys/eap_hdd_key.bin`. Fluxo e pendências: [`../outros/docs/MONTAGEM_HD_INTERNO.md`](../outros/docs/MONTAGEM_HD_INTERNO.md) e [`../outros/docs/BACKLOG_MOUNT.md`](../outros/docs/BACKLOG_MOUNT.md). Obtenção da chave (payload no Orbis): [`../outros/docs/ENVIO_DE_PAYLOADS.md`](../outros/docs/ENVIO_DE_PAYLOADS.md) |
| `scripts/provisiona-chave.sh` | Instala a chave EAP do usuário (`--ssh root@IP` ou `--rootfs DIR`), normaliza/valida e confere montando o `sda27` |
| `ssh-startup.sh` + `ssh-auto-startup.service` | **Legado, não entra mais na imagem**: o rootfs já é o sistema (`root=LABEL=psxitarch`); o SSH sobe pelo `sshd.service` normal |
| `firmware_gpu/`, `firmware_wifi/` | Firmware genuíno (Gladius/amdgpu, MediaTek MT7668) |
| `hardware_ps4_real/` | Coletas de hardware feitas no console real (`/proc`, `lspci`, …) |
| `mesa/` | Patch + build do Mesa que reconhece `CHIP_GLADIUS`/`CHIP_LIVERPOOL` |
| `monitor_edid/` | EDID do monitor e utilitários de vídeo |
| `ps4_tv_edid.bin` | EDID injetado no initramfs (`drm.edid_firmware`) |
| `scripts/` | `promote-release.sh`, `provisiona-chave.sh` (chave EAP do usuário), `ps4_crypt_mount.sh` (legado), `build-image-docker.sh` (build em container Arch), `fetch_gladius_fw.py` |
| `RELEASE/` | Artefatos de distribuição (`v1.0.0` versionado; demais tags são build local) |

## Regras que valem para esta frente

- **Label `psxitarch` é obrigatória** na partição root: o initramfs (gerado pelo
  **mkinitcpio**) resolve `root=LABEL=psxitarch` via `blkid`/udev
  (`resolve_device` → `poll_device`) e monta em `/sysroot`; se a label não
  bater, o `init` cai no shell de emergência ("Failed to mount the real root
  device"). Outra label = boot quebrado.
- `mkinitcpio.conf` **sempre** `COMPRESSION="gzip"` (o kernel 7.0 Baikal não tem
  `CONFIG_RD_ZSTD`).
- `bootargs` usa UART MMIO (`uart8250,mmio32,0xC890E000`) + `console=tty0` e
  `rootwait` — nunca `console=ttyS0` nem `rootdelay=N`.
- Deploy só com os 4 arquivos da tag presentes, conferindo MD5. Sem fallback
  silencioso para o initramfs genérico.
- **Nunca montar direto em `/mnt`**: use subdir dedicado
  (`/mnt/ps4_burn_7.0`, `/mnt/ps4_rootfs_7.0`, `/mnt/ps4_internal/...`).
- `BUILD_ROOT` do build da distro pode ser qualquer ponto de montagem que suporte
  chroot/mount (ex: `/mnt/hdauxiliar/...`).
- Regras completas: [`../AGENTS.md`](../AGENTS.md).
