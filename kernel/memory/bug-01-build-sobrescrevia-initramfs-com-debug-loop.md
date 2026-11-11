# Bug corrigido 2026-07-24: 01-build-image-7.0.sh sobrescrevia initramfs com o loop DEBUG de ontem

## O que acontecia

Nas linhas 445-448 (antes da correção), depois de gerar um initramfs novo via `mkinitcpio`
(refletindo o rootfs recém-criado por `01-build-image-7.0.sh`: pacotes pacstrap de hoje +
`mts.ko` recompilado local), o script sobrescrevia incondicionalmente esse arquivo com
`initramfs-7.0-20260723-mts-autoeth0.cpio.gz` — rotulado no comentário como "initramfs oficial
com vídeo OK", o que é falso: esse arquivo é do tipo **DEBUG** (ver taxonomia RELEASE vs DEBUG
no `CLAUDE.md` da raiz do projeto), cujo `/init` é um script busybox com loop de diagnóstico que
**nunca monta o rootfs real nem faz `switch_root`**.

Confirmado ao vivo em 2026-07-24 (usuário rodou `01-build-image-7.0.sh` + `02-burn-image-7.0.sh
/dev/sda`, gravação "bem-sucedida" mas o PS4 desligou sem mostrar vídeo):
- `cmp` mostrou que `initramfs-7.0.cpio.gz` gravado no HD era **byte-a-byte idêntico** a
  `initramfs-7.0-20260723-mts-autoeth0.cpio.gz` (DEBUG), não ao
  `initramfs-7.0-20260723-RELEASE.cpio.gz` (baseline oficial).
- `bzImage-7.0` e `bootargs-7.0.txt` gravados eram idênticos aos da RELEASE validada — só o
  initramfs estava errado.
- Abrindo o `/init` de cada um: RELEASE = `better-initramfs` real (shell script que faz
  `switch_root`); mts-autoeth0 = script busybox (`#!/bin/busybox sh`) com comentário próprio
  dizendo que é loop de diagnóstico e que "UDP via eth0: historicamente nunca funcionou".

## Consequência

Todo o trabalho de rootfs feito pelo `01-build` (pacotes novos, `mts.ko` recompilado com as
mudanças pendentes em `mts.c`) era gravado na partição ext4 mas **nunca seria montado** — o
initramfs real gravado no boot ignorava essa partição. Ou seja, a cada rodada de
`01-build`+`02-burn`, o que se testava de fato no console era sempre o loop DEBUG de
2026-07-23, não o sistema atual.

**Isso NÃO explica com certeza** o sintoma relatado ("PS4 desligou, sem vídeo algum") — sessões
anteriores com esse mesmo DEBUG loop mostravam vídeo normalmente (o vídeo depende do kernel/EDID
de hardware, não do initramfs). Então o sintoma de "sem vídeo" pode ter uma causa adicional
ainda não identificada (física/burn/hardware) — não descartar essa possibilidade em investigações
futuras.

## Correção aplicada

Removido o bloco de sobrescrita. Agora `01-build-image-7.0.sh` usa diretamente o initramfs que o
próprio `mkinitcpio` acabou de gerar para o rootfs da build atual:

```bash
echo "=== Usando initramfs recem-gerado (mkinitcpio, reflete o rootfs desta build) ==="
cp "$ROOTFS_DIR/boot/initramfs-$KVER_FULL.img" "$BOOT_DIR/initramfs-7.0.cpio.gz"
```

Isso garante que cada `01-build` grava um initramfs que efetivamente monta e faz `switch_root`
para o rootfs recém-construído (pacotes + `mts.ko` da vez), em vez de silenciosamente testar um
artefato antigo do dia anterior.

## Como aplicar / verificar

Antes de gravar de novo, é possível conferir rapidamente se o initramfs gerado é do tipo certo:

```bash
mkdir -p /tmp/chk && cd /tmp/chk
zcat boot_referencia/initramfs-7.0.cpio.gz | cpio -idm --quiet
file init   # deve dizer "POSIX shell script" (mkinitcpio/better-initramfs), NÃO "busybox sh script"
```
