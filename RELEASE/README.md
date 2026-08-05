# RELEASE — Artefatos Compilados

## 📦 Versão de distribuição: `v1.0.0`

A pasta `v1.0.0/` é a **versão de distribuição** oficial (versionada no git):
`bzImage-7.0-v1.0.0`, `config-7.0-v1.0.0`, `bootargs-7.0-v1.0.0.txt`,
`initramfs-7.0-v1.0.0.cpio.gz` + README com features e deploy. Build de origem:
`20260801-kvm-rtc-sata-final` (KVM-AMD + RTC via ICC + SATA interno). Ver
`v1.0.0/README.md`.

## Demais tags (build output local, gitignored)

O pipeline oficial (`00-build-kernel-7.0.sh`, `01-build-image-7.0.sh`,
`deploy-boot-7.0.sh`) continua gravando em `distros/arch_minimal_v2/boot_referencia/`
— as tags aqui são montadas por:

```bash
scripts/promote-release.sh <TAG> [--no-tar]
```

Cada subdiretório `<TAG>/` contém:
- `bzImage-7.0-<TAG>` — kernel compilado (ThinLTO, Baikal)
- `config-7.0-<TAG>` — config usada no build
- `bootargs-7.0-<TAG>.txt` — bootargs validados ao vivo
- `initramfs-7.0-<TAG>.cpio.gz` — initramfs da tag
- `arch_minimal_v2-7.0-<TAG>.tar` — **symlink** para o tarball da distro
  (`distros/arch_minimal_v2/arch_minimal_v2-7.0.tar`, ~16GB, gravado por
  `01-build-image-7.0.sh`). Symlink para não duplicar 16GB.
- `sha256sums.txt` — checksums dos 4 artefatos + tar (conteúdo real)

> ⚠️ `/mnt/t` é NTFS: os artefatos acima são binários simples e podem morar aqui,
> mas o **source do kernel NÃO** — ele fica em ext4 (`/mnt/hdauxiliar/temp/
> kernel_build_7.0`), acessível via symlink `kernels/ps4-baikal-7.0.8-kernel`.
> Ver `memory/filesystem-ntfs-mnt-t-restricao.md`.

## Baseline atual (recomendado)

| Tag | Status | Conteúdo |
|-----|--------|----------|
| `20260730-sata-polling-fase-ab` | 🏆 OFICIAL | GBE + SATA interno funcional (UDMA/100), vídeo OK. Rollback: `deploy-boot-7.0.sh 20260730-sata-polling-fase-ab` |
| `20260730-sata-reverted` | Ponto de rollback anterior | SATA polling sem instrumentação |

## Promovendo uma tag nova

```bash
sudo ./distros/arch_minimal_v2/00-build-kernel-7.0.sh <NOVA_TAG>
sudo ./distros/arch_minimal_v2/deploy-boot-7.0.sh <NOVA_TAG>   # testou no PS4, OK
./scripts/promote-release.sh <NOVA_TAG>
```

Nunca promover tag não testada ao vivo no PS4.
