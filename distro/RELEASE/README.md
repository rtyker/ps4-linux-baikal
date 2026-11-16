# RELEASE — Artefatos Compilados

Pasta da **frente 2** (`distro/`). Recebe as tags promovidas a partir dos artefatos que o
build da **frente 1** grava em `distro/boot_referencia/`.

## 📦 Versão de distribuição: `v1.0.0`

A pasta `v1.0.0/` é a **versão de distribuição** oficial (versionada no git):
`bzImage-7.0-v1.0.0`, `config-7.0-v1.0.0`, `bootargs-7.0-v1.0.0.txt`,
`initramfs-7.0-v1.0.0.cpio.gz` + README com features e deploy. Build de origem:
`20260801-kvm-rtc-sata-final` (KVM-AMD + RTC via ICC + SATA interno). Ver
[`v1.0.0/README.md`](v1.0.0/README.md).

> 🟢 **É hoje a única cópia íntegra de uma tag neste clone:** o `distro/boot_referencia/`
> original foi perdido. O snapshot de 2026-08-01 que servia de conferência (MD5 byte a byte)
> foi apagado em 2026-11-11 — esta pasta passou a ser a única fonte dessa tag.

## Demais tags (build output local, gitignored)

O pipeline continua gravando em `distro/boot_referencia/` (o build da frente 1 escreve lá) — as
tags aqui são montadas pela frente 2:

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
> `distro/boot_referencia/`; o **rootfs** e o Mesa patchado são build output de `distro/`.
> O source do kernel mora em `kernel/kernel_build_7.0` (dentro do repo,
> gitignored; exige ext4).

## Baseline e rollback — estado real (2026-11-11)

| Tag | Situação |
|-----|----------|
| `20260801-kvm-rtc-sata-final` (base do `v1.0.0`) | ✅ artefatos aqui, MD5 conferido. ⚠️ sem boot de validação registrado para o fix de SATA `.7` |
| `20260730-sata-polling-fase-ab` (baseline validado ao vivo) | ❌ **artefatos perdidos** — não existem em disco nenhum; rollback impossível |
| `20260730-sata-reverted` | ❌ artefatos perdidos |
| `v7.0-20260722-clean-video-ok` / `20260720-sky2len-fix` | ❌ artefatos perdidos |

Recuperação possível hoje: apenas `v1.0.0/` (os 3 snapshots de 2026-08-01 foram apagados em
2026-11-11). Ver a seção "ESTADO DOS ARTEFATOS" em
[`../../AGENTS.md`](../../AGENTS.md).

## Promovendo uma tag nova

```bash
sudo ./kernel/00-build-kernel-7.0.sh <NOVA_TAG>     # frente 1
sudo ./distro/deploy-boot-7.0.sh <NOVA_TAG>         # frente 2 — testou no PS4, OK
./distro/scripts/promote-release.sh <NOVA_TAG>      # promove
```

Nunca promover tag não testada ao vivo no PS4.
