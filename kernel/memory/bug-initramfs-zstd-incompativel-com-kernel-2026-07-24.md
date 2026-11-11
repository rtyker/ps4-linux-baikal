# Bug corrigido 2026-07-24: mkinitcpio.conf usava COMPRESSION="zstd", kernel 7.0 só suporta gzip/xz/lzo/lz4/lzma

## Sintoma ao vivo

Após a correção anterior ([bug-01-build-sobrescrevia-initramfs-com-debug-loop](bug-01-build-sobrescrevia-initramfs-com-debug-loop.md)),
o `01-build-image-7.0.sh` passou a usar o initramfs recém-gerado pelo `mkinitcpio` em vez do
DEBUG loop antigo. Ao gravar e testar no PS4 real, o boot falhou com:

```
RAMDISK: Couldn't find valid RAM disk image starting at 0.
/dev/root: Can't open blockdev
VFS: Cannot open root device "LABEL=psxitarch" or unknown-block(0,0): error -6
```

(A tempestade de erros `ata1.00`/`sda` no mesmo dmesg é o HD **interno** do PS4, não o nosso HD
USB — o `sdb` aparece corretamente enumerado com `sdb1`/`sdb2` do tamanho certo. Não relacionado
ao cabo de rede frouxo mencionado pelo usuário nem à causa deste bug.)

## Causa raiz confirmada

`distros/arch_minimal_v2/01-build-image-7.0.sh` gera `/etc/mkinitcpio.conf` com
`COMPRESSION="zstd"` (linha ~386). Mas `CONFIG_RD_ZSTD` **não está habilitado** no `.config` do
kernel 7.0 Baikal (`/mnt/hdauxiliar/temp/kernel_build_7.0/.config` e
`boot_referencia/config-7.0`) — só existem `CONFIG_RD_GZIP=y`, `CONFIG_RD_BZIP2=y`,
`CONFIG_RD_LZMA=y`, `CONFIG_RD_XZ=y`, `CONFIG_RD_LZO=y`, `CONFIG_RD_LZ4=y`.

Diagnóstico feito inspecionando o `initramfs-7.0.cpio.gz` gravado:
- Estrutura correta: segmento `early_cpio` (não comprimido, ~10KB, contém só o esqueleto
  `bin/lib/lib64/sbin -> usr/*` + `var/run`) seguido do payload principal.
- Payload principal tinha assinatura mágica zstd (`28 b5 2f fd`) no offset 0x2800 — **não**
  gzip (`1f 8b`).
- Os initramfs que sempre funcionaram (`initramfs-7.0-20260723-RELEASE.cpio.gz`,
  `initramfs-7.0-20260723-mts-autoeth0.cpio.gz`) têm magic `1f 8b` (gzip) desde o primeiro byte,
  sem segmento `early_cpio` separado.

Resultado: o kernel processava o `early_cpio` (por isso aparecem só os symlinks básicos), mas
não conseguia descomprimir o payload principal zstd — ficava sem `/init` executável, caía no
fallback de RAM disk legado (que também falha, pois não é esse o formato), e por fim tentava
montar `root=` direto nos discos físicos sem sucesso.

## Correção aplicada

`distros/arch_minimal_v2/01-build-image-7.0.sh`: `COMPRESSION="zstd"` → `COMPRESSION="gzip"` no
heredoc do `mkinitcpio.conf`.

## Como verificar antes de gravar de novo

```bash
xxd boot_referencia/initramfs-7.0.cpio.gz | head -1
# deve começar com "1f8b 0800" (gzip) já no primeiro byte, IGUAL ao RELEASE/DEBUG antigos.
```

Se aparecer `0707 0100...` (cpio sem compressão) no início, o payload comprimido em algum ponto
mais adiante do arquivo deve ter magic `1f 8b` (gzip) e NÃO `28 b5 2f fd` (zstd) — do contrário
o boot vai falhar do mesmo jeito.
