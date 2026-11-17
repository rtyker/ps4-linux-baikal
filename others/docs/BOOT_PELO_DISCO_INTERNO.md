# Caminho alternativo: boot do kernel pelo disco INTERNO do PS4

**Status (2026-11-17): preparado, aguardando a confirmação do primeiro boot.** Os arquivos foram enviados e conferidos por MD5; o boot em si ainda não foi confirmado (o usuário viu o boot parar na altura do `wlan` uma vez, suspeita do HD USB; novo boot em andamento). Este documento muda de status quando o `bootsrc=internal` aparecer no `/proc/cmdline`.

## Ideia

O payload (`ps4-linux-payloads/linux/main-aio.c`) procura cada arquivo de boot, **de forma independente**, nesta ordem:

1. `/mnt/usb0/<arquivo>`
2. `/mnt/usb1/<arquivo>`
3. `/data/linux/boot/<arquivo>`  ← **pasta do disco interno usada aqui**
4. `/user/system/boot/<arquivo>`

Se o USB não tiver o arquivo, o payload usa o do disco interno. Assim o kernel e o initramfs saem do HD do PS4 (Orbis), sem depender do USB. **O rootfs continua no USB** (`root=LABEL=psxitarch`): o USB ainda precisa estar plugado.

## Arquivos que o payload lê

| Arquivo | Obrigatório | Observação |
|---|---|---|
| `bzImage` | sim | kernel |
| `initramfs.cpio.gz` | sim | o nome precisa ser exatamente esse (o `.zip` antigo do interno não casa) |
| `bootargs.txt` | não | sem ele o payload usa um cmdline padrão **sem** `root=LABEL=psxitarch` |
| `vram.txt` | não | valor em MB; sem ele o padrão é 1024. Tem prioridade sobre o payload carregado |

## Script oficial deste caminho: `distro/deploy-boot-ftp-7.0.sh`

```bash
./distro/deploy-boot-ftp-7.0.sh <TAG> [--vram MB] [--no-marker] [--dry-run] [--allow-usb-conflict]
```

Não toca no `deploy-boot-7.0.sh` (que continua escrevendo no USB). O que faz: confere que o FTP responde (só existe no Orbis); recusa seguir se o USB tiver arquivos de boot (ele tem prioridade); baixa para `~/ps4-boot-internal-backup-<data>/` o que já está no PS4; sobe tudo como `.part`, confere o MD5 baixando de volta, e só então renomeia para o nome final; confere de novo os nomes finais; grava `active-tag.txt` com a tag; acrescenta `bootsrc=internal` ao `bootargs` (use `--no-marker` para não). O `vram.txt` do PS4 **só é tocado com `--vram MB`** (o `vram.txt` do repositório é 1024 e o do PS4 está em 4096, então não há valor padrão). Testado em 2026-11-17: `--dry-run` e uma execução real com a tag `20261117-dp-diag2` (idempotente, MD5 igual ao já enviado). O FTP do GoldHEN aceita upload, rename (inclusive por cima de arquivo existente) e DELE: testado.

## Procedimento manual equivalente (FTP do GoldHEN, porta 2121, PS4 em modo Orbis)

```bash
F=ftp://192.168.6.130:2121/data/linux/boot
curl --ftp-create-dirs -T bzImage           $F/bzImage
curl --ftp-create-dirs -T initramfs.cpio.gz $F/initramfs.cpio.gz
curl --ftp-create-dirs -T bootargs.txt      $F/bootargs.txt
curl --ftp-create-dirs -T vram.txt          $F/vram.txt
# conferir: baixar de volta e comparar o md5 com o arquivo local
curl -o /tmp/chk $F/bzImage && md5sum /tmp/chk bzImage
```

1. **Mover, não copiar:** para não haver ambiguidade, **remova** esses 4 arquivos da partição BOOT do USB (o USB tem prioridade sobre o interno). Faça isso só depois de conferir o MD5 das cópias internas e de ter backup local.
2. **Marcador de prova:** coloque `bootsrc=internal` no fim do `bootargs.txt` interno. O kernel ignora o parâmetro e ele aparece em `/proc/cmdline`; se aparecer, o `bootargs` veio do interno.
3. O `FTP` só existe no Orbis (`192.168.6.130`); depois do `kexec` as portas 9090 e 2121 somem.

## Estado feito em 2026-11-17

- Tag em uso: `20261117-dp-diag2` (kernel com o patch de diagnóstico do DP, `vram.txt=4096`).
- Enviados e conferidos (MD5 enviado = baixado): `bzImage` `2db126505d26`, `initramfs.cpio.gz` `9ba2bddd3097`, `bootargs.txt` `58a51d785b3f` (com `bootsrc=internal`), `vram.txt` `102e7bda3ff4`.
- `/data/linux/boot/` estava vazio antes.
- Os 4 arquivos foram **removidos** do USB (BOOT) e há um `BOOT-MOVIDO.txt` lá. Backup local: `~/ps4-boot-usb-backup-20261117/`.
- Registro: `test_history` (fase "Boot pelo disco interno").

## Cuidados

- **`distro/deploy-boot-7.0.sh` conflita com este caminho:** ele grava `bzImage`, `initramfs.cpio.gz`, `bootargs.txt` e `vram.txt` no USB, e o USB volta a ter prioridade. Para trocar de tag com este caminho, envie os arquivos novos por FTP e **não** use o `deploy-boot` (ou remova os 4 do USB depois dele).
- **Arquivos antigos no interno** em `/user/system/boot/` (`bzImage` de 06/01/2026, `initramfs.cpio.zip`, `psxitarch.tar.xz` de 3,7 GB): só seriam usados se faltasse o arquivo em `/data/linux/boot/`. Marcados para remoção depois (BACKLOG, item 7b); não foram tocados.
- **Rollback:** copie os 4 arquivos do backup (`~/ps4-boot-usb-backup-20261117/`) de volta para a BOOT do USB, ou rode `deploy-boot-7.0.sh <TAG>` com o HD no PC. Com os arquivos no USB, ele passa a ter prioridade de novo.
- **O que este caminho NÃO resolve:** o rootfs continua no USB, então as falhas de I/O do HD USB (BACKLOG, item 5) continuam afetando o boot. Para tirar o USB por completo é preciso um rootfs no disco interno, o que hoje não cabe (ver o levantamento em `BACKLOG.md`: o disco interno não tem espaço livre, e a única partição grande é a de dados do Orbis).
