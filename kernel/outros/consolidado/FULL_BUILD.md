# Plano de Build Completo — PS4 Linux Baikal

## Visão Geral do Pipeline

```
[0. Pré-build]           mesa/01-build-mesa.sh  (opcional, recomendado)
                          sudo scripts/build_mts_module.sh  (opcional, recomendado)
[1. Commit + Tag]        git tag <TAG>
[2. 00 Kernel]           sudo ./00-build-kernel-7.0.sh <TAG>
[3. 01 Image]            sudo ./01-build-image-7.0.sh
[4. 02 Burn]             sudo ./02-burn-image-7.0.sh /dev/sda
```

**TAG** é a string única que identifica esta build (ex: `20260725-full-gbe-release`).
Usada como git tag, sufixo dos artefatos em `boot_referencia/` e nome do initramfs
associado.

---

## Verificação: Scripts já copiam mesa e mts.ko?

### Mesa patchado → SIM, já integrado
`01-build-image-7.0.sh:341-363` verifica `mesa/mesa-ps4-gladius-liverpool-latest.tar.xz`.
Se existir, extrai para `/opt/mesa-ps4-patched` no rootfs e persiste
`LD_LIBRARY_PATH`/`LIBGL_DRIVERS_PATH` em `/etc/environment`.

**Pré-requisito:** rodar `mesa/01-build-mesa.sh` antes do passo 01 se quiser o patch
ativado. O script gera `mesa/mesa-ps4-gladius-liverpool-latest.tar.xz` consumido
automaticamente pelo pipeline.

### mts.ko do projeto → SIM, já integrado
`01-build-image-7.0.sh:317-328` verifica `drivers_mts/build/mts.ko`. Se existir,
copia para `lib/modules/<KVER>/kernel/drivers/net/ethernet/sony/mts.ko` dentro do
rootfs, sobrescrevendo o que veio do `modules_install` (que compila o mts da
árvore do kernel em `00-build-kernel-7.0.sh:188-201`).

**Pré-requisito:** rodar `sudo scripts/build_mts_module.sh` antes do passo 01 se
quiser garantir a versão mais recente do mts.ko no rootfs.

---

## Plano Passo a Passo

### Passo 0 — Pré-build (opcional, recomendado)

```bash
# 0a. Mesa patchado (Gladius/Liverpool) — gera mesa/mesa-ps4-gladius-liverpool-latest.tar.xz
cd mesa && ./01-build-mesa.sh && cd ..

# 0b. MTS module isolado — gera drivers_mts/build/mts.ko
sudo scripts/build_mts_module.sh
```

### Passo 1 — Commit + Tag

```bash
TAG="20260725-full-gbe-release"

git status                     # conferir o que vai
git add -A
git commit -m "Full build $TAG"
git tag -a "$TAG" -m "Full build $TAG"
```

### Passo 2 — Build Kernel (00)

```bash
cd distros/arch_minimal_v2
sudo ./00-build-kernel-7.0.sh "$TAG"
```

Gera em `boot_referencia/`:
- `bzImage-7.0-<TAG>`
- `config-7.0-<TAG>`

O script já copia `mts.c` e `mts.h` de `../../drivers_mts/` para a árvore do kernel
(linhas 188-201), incluindo o driver `mts` como módulo (`CONFIG_MTS_GBE=m`).

### Passo 3 — Link genérico para 01

`01-build-image-7.0.sh` referencia `boot_referencia/bzImage-7.0` (sem tag) e
`boot_referencia/bootargs-7.0.txt`:

```bash
cd distros/arch_minimal_v2
ln -sf "bzImage-7.0-$TAG" boot_referencia/bzImage-7.0
cp boot_referencia/bootargs-7.0.txt "boot_referencia/bootargs-7.0-$TAG.txt"
```

### Passo 4 — Build Image (01)

```bash
sudo ./01-build-image-7.0.sh
```

O script:
1. Cria rootfs Arch via `pacstrap`
2. Instala módulos do kernel via `make modules_install`
3. **Sobrescreve mts.ko** com o de `drivers_mts/build/mts.ko` (se existir)
4. **Instala mesa patchado** de `mesa/mesa-ps4-gladius-liverpool-latest.tar.xz`
   (se existir) em `/opt/mesa-ps4-patched` + `/etc/environment`
5. Gera initramfs via `mkinitcpio`
6. Grava em `boot_referencia/`:
   - `initramfs-7.0.cpio.gz`
   - `bootargs-7.0.txt` (atualizado)

### Passo 5 — Versionar initramfs com a tag

O `deploy-boot-7.0.sh` e a convenção do repositório exigem initramfs por tag:

```bash
cp boot_referencia/initramfs-7.0.cpio.gz "boot_referencia/initramfs-7.0-$TAG.cpio.gz"
```

### Passo 6 — Burn (02)

```bash
# Conectar o HD/SSD alvo antes
sudo ./02-burn-image-7.0.sh /dev/sda
```

O script:
1. Particiona (sda1=200MB FAT32, sda2=restante ext4 com label `psxitarch`)
2. Formata e monta
3. Copia boot files de `boot_referencia/` (bzImage, initramfs.cpio.gz, bootargs.txt, vram.txt)
4. Extrai rootfs tarball para sda2
5. Desmonta

---

## Pós-Burn

Deploy rápido (só trocar boot sem recriar rootfs):

```bash
sudo ./deploy-boot-7.0.sh "$TAG"
```

Conectar o HD ao PS4, enviar payload e testar.

---

## Observações

- `01-build-image-7.0.sh:317-328`: **já copia** `drivers_mts/build/mts.ko` sobrescrevendo
  o módulo da árvore do kernel. ✅
- `01-build-image-7.0.sh:341-363`: **já copia** mesa patchado de
  `mesa/mesa-ps4-gladius-liverpool-latest.tar.xz`. ✅
- O pipeline não exige `consolidado/build_payloads.sh` — payloads são independentes
  (repositório separado `ps4-linux-payloads/`).
- A tag deve ser única por build. Usar `git tag -l` para listar as existentes.
- `boot_referencia/bzImage-7.0` (genérico) é sobrescrito a cada build; o versionado
  `bzImage-7.0-<TAG>` mantém o histórico.
- Se pular o mesa build, o rootfs usará o mesa oficial do Arch (com bug de corrupção
  visual em CHIP_GLADIUS/CHIP_LIVERPOOL — ver `consolidado/MESA_GLADIUS_LIVERPOOL_FIX.md`).
- Se pular `scripts/build_mts_module.sh`, o rootfs usará o mts.ko compilado como
  parte do `00-build-kernel-7.0.sh` (que já compila `drivers_mts/mts.c` na árvore).