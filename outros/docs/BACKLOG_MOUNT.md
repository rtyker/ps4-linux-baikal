# BACKLOG — Montagem de Partições (HD Interno PS4 /dev/sda)

> Projeto: PS4 Linux Baikal — Frente 2 (Distro)
> Fonte: levantamento feito em `distro/monta_particao.sh`, `distro/desmonta_particao.sh`, `distro/automount.sh`, `distro/01-build-image-7.0.sh`, `distro/02-burn-image-7.0.sh`, `outros/docs/BACKLOG.md`, `outros/docs/LICOES_APRENDIDAS.md` e `AGENTS.md`.
>
> **🏆 RESOLVIDO em 2026-11-13 (validado ao vivo):** `sda27` (user/UFS2, 884 GiB), `sda29` (eap_user/UFS2) e
> `sda25` (update/FAT32) **montam read-only**. O segredo era o **IV offset** `(dev_no - 1) << 32`,
> aplicado via `dmsetup` porque o `cryptsetup` não tem como definir `iv_offset`.
> Detalhes técnicos em [`MONTAGEM_HD_INTERNO.md`](MONTAGEM_HD_INTERNO.md) §2. `sda13` foi descartado
> (é o swap antigo, chave versioned — não é UFS2 nem EAP).
> 
> **Não confundir com:** Baikal Memory SPM (`baikal-memory.ko`) e RTC via ICC (`rtc-ps4-icc`), que já estão concluídos e testados (tag `20261113-baikal-memory-fase5`). Este BACKLOG trata apenas de montagem de partições.

**Legenda de status:** ✅ executado · 📝 verificado/documentado · ⏳ pendente de hardware (PS4 real) · 🔴 bloqueante

---

## 1. Visão geral

Existem duas camadas de montagem no projeto:

| Camada | Scripts | Status |
|--------|---------|--------|
| **HD USB de boot** (partição BOOT + rootfs `psxitarch`) | `02-burn-image-7.0.sh`, `deploy-boot-7.0.sh` | ✅ Concluído e validado ao vivo |
| **Partições do HD interno PS4** (`sda27` user/UFS2, `sda29` eap_user/UFS2, `sda25` update/FAT32) | `monta_particao.sh`, `desmonta_particao.sh`, `desmonta_todas.sh`, `automount.sh` | ✅ **Funcional e validado ao vivo (2026-11-13)** — `sda13` é não-montável por design |

Este BACKLOG foca na camada 2 (HD interno).

---

## 2. O que está feito (já integrado ao build)

### 2.1 Scripts de montagem nativa (copiados para o rootfs por `01-build-image-7.0.sh`, linhas 579–585)

- `distro/monta_particao.sh` → `/usr/local/bin/monta_particao.sh` — **script único de produção** (MOUNT-02)
- `distro/desmonta_particao.sh` → `/usr/local/bin/desmonta_particao.sh`
- `distro/desmonta_todas.sh` → `/usr/local/bin/desmonta_todas.sh` (MOUNT-07)
- `distro/automount.sh` → `/usr/local/bin/automount.sh`

Todos com `chmod +x` e idempotentes.

### 2.2 Serviço systemd

- `ps4-automount.service` (oneshot, `RemainAfterExit=yes`)
- `ExecStart=/usr/local/bin/automount.sh`
- `ExecStop=/usr/local/bin/desmonta_todas.sh` (MOUNT-07 — antes era `desmonta_particao.sh /dev/sda27` fixo)
- Habilitado em `multi-user.target.wants`
- `automount.sh` detecta o HD interno (`sda` ou `sdb`) e monta **27 (user), 29 (eap_user) e 25 (update)**;
  não toca em `sda13` (swap antigo, não montável)

### 2.3 Permissões e udev

- `/etc/sudoers.d/ps4-hdd`: `ps4 ALL=(ALL:ALL) NOPASSWD: ALL`
- `/etc/udev/rules.d/99-ps4-disk-permissions.rules`: modo `0666` para `sda*`, `dm-*`, `mapper/ps4_*`
- `/etc/udev/rules.d/99-ps4-media.rules`: labels PFS/ufs2 para udisks2
- Diretório `/mnt/ps4_internal` com `chmod 777`

### 2.4 Utilitários PFS (opcionais, copiados se existirem)

- `pkg_pfs_tool` (Jaguar `btver2`) + `config.ini` — **binário NÃO está compilado** no clone (ver MOUNT-06)
- `ps4_pfs_fuse` — **binário NÃO está compilado** no clone (ver MOUNT-06)
- O build avisa com `AVISO` e pula se não encontrados (não bloqueia o build, mas bloqueia montar PFS).

### 2.5 Chave EAP

- Local canônico: `/etc/ps4-keys/eap_hdd_key.bin` (32 B, root, modo 600) — pasta `/etc/ps4-keys/`
  (700) criada pelo build, com `LEIA-ME.txt` (sem segredo).
- Ordem de busca no `monta_particao.sh`: `$PS4_KEYS_FILE` → `$PS4_KEYS_DIR/eap_hdd_key.bin`
  → `$PS4_KEYS_DIR/ps4_keys.bin` → `$PS4_KEYS_DIR/eap_hdd_key.hex` → `$PS4_KEYS_DIR/eap_hdd_key.txt`
  → `/etc/ps4_keys.bin` → `/tmp/keys.bin` (os dois últimos por compatibilidade).
- **O build NÃO copia a chave** para o rootfs; quem instala é o dono do console
  (`distro/scripts/provisiona-chave.sh`, ver MOUNT-08).
- Chave do console de teste confirmada ao vivo (EAPDumper, 2026-11-13): sha256
  `990c1aa3b821c4aa9a9acb0d25127eb6d3227e5f97232ffd6eee5a4d9511c8bf`. **A chave em si não é
  registrada em documento** — está em `.env.keys` (gitignored) e no console.
- **Dump kernel Orbis (`kmem_dump_1252.bin`, offset `0xae7ef0`):** ERK `7fcf0536…476af6` — **cópia de debug/rodata, NÃO é a chave ativa** (testada: não decripta as partições).
- **Obtenção:** só via payload **EAPDumper** rodando no Orbis (GoldHEN). Fonte em
  `outros/tools/ps4_hdd_tools/EAPDumper/`; build com
  `outros/tools/ps4_hdd_tools/build_eapdumper.sh` (ver MOUNT-09) e envio pelo procedimento canônico
  [`ENVIO_DE_PAYLOADS.md`](ENVIO_DE_PAYLOADS.md) (`outros/scripts/ps4_send_payload.sh`).


---

## 3. Tarefas

### P0 — Bloqueantes

| ID | Tarefa | Status | Detalhe |
|----|--------|--------|---------|
| MOUNT-01 | **Resolver tweak/IV da partição `sda27`** | ✅ | **RESOLVIDO 2026-11-13.** O IV offset é `(dev_no - 1) << 32` (psdevwiki, CUH-1100+): `sda27`→`111669149696`, `sda29`→`120259084288`, `sda25`→`103079215104`. O `cryptsetup` **não** aplica isso (`--offset`/`--skip` são data offset; `--offset 111669149696` aborta com "beyond real size"); o mapper é criado com `dmsetup create -r ... "0 <sec> crypt aes-xts-plain64 <key_hex> <iv_offset> <dev> 0"`. Validado: magic UFS2 `0x19540119` em `0x1055C`, `blkid` = `ufs` v2, mount ro OK (884 GiB, 485 GiB usados). `sda13` **não é montável** (swap antigo, chave versioned). |
| MOUNT-02 | **Unificar scripts de montagem** | ✅ | `distro/monta_particao.sh` é o script único de produção: calcula o iv_offset, cria/recria o mapper via `dmsetup -r` (detecta mapper antigo com IV errado e recria), detecta o FS com `blkid -p` (UFS2/vfat/…) e monta ro. `distro/scripts/ps4_crypt_mount.sh` virou shim legado que delega para ele (não vai para o rootfs). |
| MOUNT-03 | **Teste ao vivo completo no PS4 real** | ✅ | Executado em 2026-11-13 no Linux 7.0.8 Baikal (`192.168.6.128`): `sda27`/`sda29`/`sda25` montados ro, leitura confirmada (`app/` com 44 títulos, `app/<TITLE>/app.pkg`, `PS4UPDATE.PUP`), `desmonta_todas.sh` limpa mounts+mappers, recriação idempotente de mapper com IV errado testada. |
| MOUNT-04 | **Corrigir contradição no BACKLOG.md** | ✅ | Cabeçalho da seção mudou de `[x] FEATURE CONCLUÍDA` para `[~] PARCIAL: sda13 OK, sda27 PENDENTE`; frase "testados com sucesso… sda13 e sda27" corrigida para refletir que só `sda13` foi comprovado. Aponta para este arquivo. |

### P1 — Não bloqueantes

| ID | Tarefa | Status | Detalhe |
|----|--------|--------|---------|
| MOUNT-05 | Documentar o fluxo completo de montagem | ✅ | Criado `outros/docs/MONTAGEM_HD_INTERNO.md` (chave → cryptsetup → mapper → UFS2/FUSE, modos de tweak, diagnóstico). |
| MOUNT-06 | Verificar `pkg_pfs_tool` e `ps4_pfs_fuse` na imagem | 📝 | Verificado: os binários **não existem** em `outros/tools/ps4_hdd_tools/pkg_pfs_tool/build/` (só fontes e CMake). O build avisa e pula. **Reescopo em 2026-11-13:** o `sda27` monta sem isso (é UFS2). Essas ferramentas servem para abrir os **containers PFS** (`app/<TITLE_ID>/app.pkg`), não a partição — virou melhoria opcional, não bloqueante. |
| MOUNT-07 | Revisar `ExecStop` do systemd | ✅ | Criado `distro/desmonta_todas.sh` (desmonta tudo em `/mnt/ps4_internal` e remove todos os mappers `ps4_*`, via `dmsetup remove` com fallback `cryptsetup remove`) e `ExecStop` atualizado para chamá-lo. |
| MOUNT-08 | Provisionamento da chave EAP pelo usuário final | ✅ | `distro/scripts/provisiona-chave.sh` (modos `--ssh root@IP` e `--rootfs DIR`): normaliza 32 B crus / 33 B / 64 hex / `.txt`, valida por sha256, instala em `/etc/ps4-keys/eap_hdd_key.bin` (root, 600) e opcionalmente prova a chave montando o `sda27`. O build cria `/etc/ps4-keys/` (700) + `LEIA-ME.txt`, instala o helper em `/usr/local/bin` e **não** embute segredo. `automount.sh` consulta `monta_particao.sh --check-key` e, sem chave, avisa uma vez e sai com 0. Testado ao vivo em 2026-11-13 (bin, hex, `.txt`, 33 B, ausência de chave). |
| MOUNT-09 | **Compilar o payload EAPDumper** (obtenção da chave EAP) | ✅ | Fonte clonado em `outros/tools/ps4_hdd_tools/EAPDumper/` (commit `d590c3b`, tag `v0.2.0`); SDK `ps4-payload-sdk` v0.9 extraído ao lado (gitignored); build por `outros/tools/ps4_hdd_tools/build_eapdumper.sh`. Gera `EAPDumper.bin` + `EAP-Scanner.bin` (83 504 B, sha256 `52e6617e…`, reprodutível). **Concluído ao vivo 2026-11-13:** enviado pelo BinLoader `:9090` em `192.168.6.130` (Orbis) e chave recuperada via FTP `:2121` — sha256 `990c1aa3…c8bf` (a chave em si fica só em `.env.keys`, não versionado). Procedimento em [`ENVIO_DE_PAYLOADS.md`](ENVIO_DE_PAYLOADS.md). |


---

## 4. Comandos de referência para teste no PS4

```bash
# 0. Antes de tudo: obter a chave EAP (payload EAPDumper no Orbis)
#    → procedimento canônico: outros/docs/ENVIO_DE_PAYLOADS.md (MOUNT-09)

# 1. Verificar scripts no rootfs
ls -l /usr/local/bin/monta_particao.sh /usr/local/bin/desmonta_particao.sh \
      /usr/local/bin/desmonta_todas.sh /usr/local/bin/automount.sh

# 2. Verificar chave EAP (32 bytes, root 600) — sem chave o automount só avisa
ls -l /etc/ps4-keys/eap_hdd_key.bin 2>/dev/null || echo "sem chave (rode distro/scripts/provisiona-chave.sh)"
monta_particao.sh --check-key

# 3. Montar jogos/dados (sda27, UFS2) — deve montar ~884 GiB
sudo /usr/local/bin/monta_particao.sh /dev/sda27
ls /mnt/ps4_internal/sda27          # addcont app appmeta bgft data savedata …

# 4. Montar eap_user e update
sudo /usr/local/bin/monta_particao.sh /dev/sda29
sudo /usr/local/bin/monta_particao.sh /dev/sda25   # FAT32: PS4UPDATE.PUP

# 5. Conferir o IV aplicado e o magic UFS2
sudo dmsetup table ps4_sda27        # campo 6 = 111669149696
sudo dd if=/dev/mapper/ps4_sda27 bs=1 skip=66908 count=4 2>/dev/null | xxd  # 1901 5419
sudo blkid -p /dev/mapper/ps4_sda27 # TYPE="ufs" VERSION="2"

# 6. Desmontar tudo
sudo /usr/local/bin/desmonta_todas.sh
```

> Regra do projeto: **nunca montar diretamente em `/mnt`**. Usar `/mnt/ps4_internal/...`.

---

## 5. Arquivos e locais de referência

| Caminho | O que é |
|---------|---------|
| `distro/monta_particao.sh` | **Script único de produção** (`iv_offset=(dev_no-1)<<32` via `dmsetup`, detecção de FS com `blkid`, mount ro) |
| `distro/desmonta_particao.sh` | Desmonta uma partição e remove o mapper |
| `distro/desmonta_todas.sh` | Desmonta tudo em `/mnt/ps4_internal` e remove todos os mappers `ps4_*` |
| `distro/automount.sh` | Detecção automática do HD interno + monta 27/29/25 |
| `distro/scripts/ps4_crypt_mount.sh` | **Legado** — shim que delega ao `monta_particao.sh` |
| `outros/tools/ps4_hdd_tools/build_eapdumper.sh` | Compila o payload EAPDumper (chave EAP) — MOUNT-09 |
| `outros/tools/ps4_hdd_tools/EAPDumper/` | Fonte do payload (terceiros) + SDK + binários gerados |
| `outros/scripts/ps4_send_payload.sh` | Envio de payload no Orbis (BinLoader `:9090`) e FTP (`:2121`) |
| `outros/docs/ENVIO_DE_PAYLOADS.md` | Procedimento canônico de injeção de payload |
| `distro/01-build-image-7.0.sh` | Copia scripts para o rootfs, configura udev/sudoers/systemd/fstab |
| `distro/02-burn-image-7.0.sh` | Grava HD USB de boot (BOOT + rootfs `psxitarch`) |
| `distro/deploy-boot-7.0.sh` | Reescreve apenas a partição BOOT |
| `outros/docs/MONTAGEM_HD_INTERNO.md` | Fluxo completo de montagem (MOUNT-05) |
| `outros/docs/BACKLOG.md` | Backlog geral (seção de montagem corrigida em MOUNT-04) |
| `outros/docs/LICOES_APRENDIDAS.md` | Lição #7: label `psxitarch` obrigatória; partição BOOT cheia |
| `outros/tools/ps4_hdd_tools/pkg_pfs_tool/` | Fontes do PFS tool (binários não compilados — MOUNT-06) |

---

## 6. Critérios de conclusão (Definition of Done)

- [x] Existe **um único** script de montagem definido e integrado ao `automount.sh` (MOUNT-02)
- [x] `BACKLOG.md` atualizado sem contradições (MOUNT-04)
- [x] Fluxo documentado em `MONTAGEM_HD_INTERNO.md` (MOUNT-05)
- [x] `ExecStop` do systemd desmonta todas as partições (MOUNT-07)
- [x] `sda27` monta e permite leitura de arquivos (MOUNT-01 resolvido — **884 GiB, 485 GiB usados**)
- [x] `sda29` (`eap_user`) e `sda25` (`update`) montam e permitem leitura
- [x] `sda13` descartado com base técnica (swap antigo, chave versioned — não é UFS2/EAP)
- [ ] `ps4_pfs_fuse`/`pkg_pfs_tool` compilados (MOUNT-06) — **opcional**: só para abrir containers `app.pkg`/`.pfs`, não para montar a partição
- [x] Chave EAP provisionada pelo usuário em `/etc/ps4-keys/eap_hdd_key.bin` (MOUNT-08 — `provisiona-chave.sh`, sem segredo no build)
- [x] Payload `EAPDumper.bin` compilado (MOUNT-09) e executado no Orbis
- [x] Teste ao vivo no PS4 real executado com sucesso (MOUNT-03)

---

## 7. Histórico de execução

**2026-11-13 (3) — 🏆 MONTAGEM DO HD INTERNO RESOLVIDA (MOUNT-01/02/03):**

- **Causa raiz:** o IV do dm-crypt nestes consoles **não** é relativo (0) nem o LBA da partição.
  É `iv_offset = (dev_no - 1) << 32` (psdevwiki, *Mounting HDD in Linux*, seção CUH-1100+).
  `sda27` → `111669149696`. Com IV=0 o mapper decifra lixo (`bad magic number`).
- **Segunda armadilha:** `cryptsetup` **não** sabe definir `iv_offset`. `--offset`/`--skip` são
  *data offset*; `--offset 111669149696` aborta ("Requested offset is beyond real size of device").
  Solução: `dmsetup create -r <name> --table "0 <sec> crypt aes-xts-plain64 <key_hex> <iv_offset> <dev> 0"`.
- **Terceira armadilha (premissa errada):** `sda27` **não é PFS** — é **UFS2**. Os jogos são
  containers PFS *dentro* dela (`app/<TITLE_ID>/app.pkg`). O driver `ufs` do kernel basta.
  `sda13` **não é UFS2 nem montável**: é o swap antigo (swapfs, chave versioned + OpenPsId).
- **Validação ao vivo** (Linux 7.0.8 Baikal, `192.168.6.128`):
  - `sda27`: magic `0x19540119` em `0x1055C`, `blkid` = `ufs` v2, mount ro, **884 GiB / 485 GiB usados**,
    `app/` com 44 títulos, `savedata`, `home`, `trophy`, `patch`, `appmeta`, `bgft`…
  - `sda29`: monta (contém `storage_stats`).
  - `sda25`: monta como FAT32 (contém `PS4UPDATE.PUP`).
  - `sda13`: com `iv_offset=12<<32` continua aleatório → descartado.
- **Scripts atualizados:** `monta_particao.sh` (iv_offset via dmsetup, recria mapper com IV errado,
  FS detectado por `blkid`), `automount.sh` (27/29/25, sem `sda13`), `desmonta_particao.sh` e
  `desmonta_todas.sh` (`dmsetup remove`), udev/`01-build-image` (labels e comentários corrigidos).
  `distro/scripts/teste_tweak_sda27.sh` (hipótese refutada) foi **removido**; `ps4_crypt_mount.sh`
  virou shim legado.
- **Estado no console:** scripts novos instalados em `/usr/local/bin`, unit com
  `ExecStop=/usr/local/bin/desmonta_todas.sh`, `automount.sh` executado com sucesso.

**2026-11-13 (2) — EAPDumper compilado (MOUNT-09):**

- Clone atualizado de `github.com/seregonwar/EAPDumper` (commit `d590c3b`; tag `v0.2.0` = `b97e943`, mesmíssimo fonte).
- SDK necessário: `ps4-payload-dev/sdk` **v0.9** (não `seregonwar/ps4-payload-sdk`, que não existe) — release
  `ps4-payload-sdk.zip` extraída em `EAPDumper/ps4-payload-sdk` (gitignored). `ps4-payload-dev/ps4-payload-sdk`
  e `ps4-payload-dev/payload-sdk` também não existem; o repo correto é `ps4-payload-dev/sdk`.
- Duas armadilhas de build encontradas e documentadas no `build_eapdumper.sh`:
  1. `cp -r` dereferencia os symlinks de `bin/` → quebra com `cannot find linker script /ldscripts/elf_x86_64.x`
     (usar `unzip` ou `cp -a`);
  2. o Makefile **não exporta** `PS4_PAYLOAD_SDK`, mas `orbis-ld` depende dela → `make` puro sempre falha.
- Build reprodutível (2 execuções, mesmo sha256): `EAPDumper.bin` = `EAP-Scanner.bin` =
  `52e6617ee5ceff727a807c8a3ba925cc5d5fffeff3fd770dad1d76fb5975eb0f` (83 504 B, ELF64 PIE x86-64).
- Release oficial v0.2.0 baixada para comparação: `73f9306da119606cde4ccd93fa0496ba4de0ec00b4850565e7b1889c84422972`
  (mesmo tamanho, `.text` menor — build deles com toolchain/commit ligeiramente diferente).
  Guardada como `EAPDumper/EAPDumper-v0.2.0-oficial.bin` (fallback).
- `main.c` e `eap_scanner.c` diferem **só em um comentário** — por isso os dois `.bin` saem idênticos.
- **Procedimento de injeção documentado** (antes só existia em histórico, com scripts perdidos):
  criado `outros/docs/ENVIO_DE_PAYLOADS.md` (GoldHEN BinLoader `:9090`, FTP `:2121`, klog `:3232`) e o
  script `outros/scripts/ps4_send_payload.sh` (`--check` / envio / `--ftp-get`). `AGENTS.md` ganhou a
  seção de regras; `INDEX_DOCUMENTACAO.md`, `MONTAGEM_HD_INTERNO.md` e `BACKLOG.md` apontam para ele.
- **Observação a reavaliar (MOUNT-01/03):** `cryptsetup` travou (>30 s, sem mensagem, inclusive com `-q`)
  ao mapear `sda13` com a chave de debug do dump. Hipótese principal: prompt/auto-detecção travando a
  sessão SSH sem TTY — repetir com `--type plain`, `--batch-mode` e `</dev/null` antes de culpar a chave.

**2026-11-13 — execução parcial do BACKLOG_MOUNT.md (sem PS4):**

- MOUNT-02 ✅ — `monta_particao.sh` unificado (LBA corrigido, `PS4_MOUNT_TWEAK`, PFS FUSE/UFS2), `ps4_crypt_mount.sh` marcado legado.
- MOUNT-04 ✅ — `BACKLOG.md` corrigido (de `[x] concluída` para `[~] parcial`).
- MOUNT-05 ✅ — criado `outros/docs/MONTAGEM_HD_INTERNO.md`.
- MOUNT-07 ✅ — criado `desmonta_todas.sh`, `ExecStop` atualizado e `automount.sh` com fallback `absolute` na 27.
- MOUNT-01 ⏳ — criado `distro/scripts/teste_tweak_sda27.sh`; falta rodar no PS4.
- MOUNT-06 📝 — verificado que `pkg_pfs_tool`/`ps4_pfs_fuse` não estão compilados.
- MOUNT-08 📝 — verificado que a chave não é provisionada pelo build.
- MOUNT-03 ⏳ — pendente de hardware.
