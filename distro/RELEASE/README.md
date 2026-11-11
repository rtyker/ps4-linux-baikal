# RELEASE — Artefatos Compilados

Pasta da **frente 2** (`distro/`). Recebe as tags promovidas a partir dos artefatos que a
**frente 1** (`kernel/boot_referencia/`) produz.

## 📦 Versão de distribuição: `v1.0.0`

A pasta `v1.0.0/` é a **versão de distribuição** oficial (versionada no git):
`bzImage-7.0-v1.0.0`, `config-7.0-v1.0.0`, `bootargs-7.0-v1.0.0.txt`,
`initramfs-7.0-v1.0.0.cpio.gz` + README com features e deploy. Build de origem:
`20260801-kvm-rtc-sata-final` (KVM-AMD + RTC via ICC + SATA interno). Ver
[`v1.0.0/README.md`](v1.0.0/README.md).

> 🟢 **É hoje a única cópia íntegra de uma tag neste clone:** o `kernel/boot_referencia/`
> original foi perdido. MD5 desta pasta confere byte a byte com o snapshot
> `/mnt/hdauxiliar/kernel_source_snapshots/kernel-src-20260801-20260801-kvm-rtc-sata-final.tar.zst`.

## Demais tags (build output local, gitignored)

O pipeline continua gravando em `kernel/boot_referencia/` (frente 1) — as tags aqui são montadas
pela frente 2:

```bash
distro/scripts/promote-release.sh <TAG> [--no-tar]
```

Cada subdiretório `<TAG>/` contém:
- `bzImage-7.0-<TAG>` — kernel compilado (ThinLTO, Baikal)
- `config-7.0-<TAG>` — config usada no build
- `bootargs-7.0-<TAG>.txt` — bootargs validados ao vivo
- `initramfs-7.0-<TAG>.cpio.gz` — initramfs da tag
- `arch_minimal_v2-7.0-<TAG>.tar` — **symlink** para o tarball da distro
  (`distro/arch_minimal_v2-7.0.tar`, ~16GB, gravado por `distro/01-build-image-7.0.sh`).
  Symlink para não duplicar 16GB.
- `sha256sums.txt` — checksums dos 4 artefatos + tar (conteúdo real)

> ⚠️ Fronteira das frentes: `bzImage`/`config`/`bootargs`/`initramfs` vivem em
> `kernel/boot_referencia/`; o **rootfs** e o Mesa patchado são build output de `distro/`.
> O source do kernel **nunca** entra no repo — fica em ext4
> (`/mnt/hdauxiliar/temp/kernel_build_7.0`), via symlink `kernel/kernels/ps4-baikal-7.0.8-kernel`.

## Baseline e rollback — estado real (2026-11-11)

| Tag | Situação |
|-----|----------|
| `20260801-kvm-rtc-sata-final` (base do `v1.0.0`) | ✅ artefatos aqui, MD5 conferido. ⚠️ sem boot de validação registrado para o fix de SATA `.7` |
| `20260730-sata-polling-fase-ab` (baseline validado ao vivo) | ❌ **artefatos perdidos** — não existem em disco nenhum; rollback impossível |
| `20260730-sata-reverted` | ❌ artefatos perdidos |
| `v7.0-20260722-clean-video-ok` / `20260720-sky2len-fix` | ❌ artefatos perdidos |

Recuperação possível hoje: `v1.0.0/` + os 3 snapshots de 2026-08-01
(`/mnt/hdauxiliar/kernel_source_snapshots/`). Ver a seção "ESTADO DOS ARTEFATOS" em
[`../../AGENTS.md`](../../AGENTS.md).

## Promovendo uma tag nova

```bash
sudo ./kernel/00-build-kernel-7.0.sh <NOVA_TAG>     # frente 1
sudo ./distro/deploy-boot-7.0.sh <NOVA_TAG>         # frente 2 — testou no PS4, OK
./distro/scripts/promote-release.sh <NOVA_TAG>      # promove
```

Nunca promover tag não testada ao vivo no PS4.
