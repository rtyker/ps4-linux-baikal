# Montagem do HD Interno do PS4 (/dev/sda) — Fluxo Completo

> Projeto: PS4 Linux Baikal — Frente 2 (Distro)
> Público-alvo: quem precisa entender/debugar a montagem das partições do HD interno do PS4.
> Backlog e pendências: [`BACKLOG_MOUNT.md`](BACKLOG_MOUNT.md).
>
> **Status (2026-11-13): FUNCIONAL e validado ao vivo.** `sda27` (jogos/dados, 884 GiB,
> 485 GiB usados), `sda29` e `sda25` montam read-only com a chave EAP. `sda13` **não é montável**
> por design (ver §1).

---

## 1. Quais partições existem e o que dá para montar

O HD interno é dividido em ~29 partições (só ímpares na prática). O que importa:

| Partição | Nome Orbis | Chave | Filesystem | Monta? |
|----------|------------|-------|------------|--------|
| `sda9`–`sda12` | system, system(b), system_ex, system_ex(b) | **SAMU** | exfat/msdos | ❌ chave não disponível |
| `sda13` | **swap antigo** (swapfs) | versioned_key + OpenPsId | — (não é FS) | ❌ **não é montável** |
| `sda17` | app_tmp | SAMU | — | ❌ |
| `sda19` | system_data | SAMU | ufs | ❌ |
| `sda25` | update | **EAP** | vfat (FAT32) | ✅ |
| `sda27` | **user** | **EAP** | **UFS2** | ✅ **(jogos, saves, dados)** |
| `sda29` | eap_user | **EAP** | UFS2 | ✅ (`storage_stats`) |
| `sda31` | app_reserved | SAMU | ufs | ❌ |

Regras práticas:

- **Só as partições com chave EAP montam**: `sda25`, `sda27`, `sda29`. As demais usam a chave
  SAMU/versioned (derivada por console, não dumpável com o EAPDumper).
- **`sda13` não é o "sistema"**: é o *swap antigo* (`swapfs`), cifrado com chave versioned +
  OpenPsId. Com o IV correto o conteúdo continua aleatório (sem magic algum) e a própria
  psdevwiki diz *"sda13 cannot be mounted for now"*. **Não** é UFS2, **não** é PFS.
- **PFS não é o filesystem da partição.** `sda27` é **UFS2**. Os jogos ficam dentro dela como
  **containers PFS** (`app/<TITLE_ID>/app.pkg`, `app.pfs`, etc.). Ou seja: para navegar em
  `/mnt/ps4_internal/sda27/app/...` basta o driver `ufs` do kernel; para *abrir o conteúdo de um
  `.pkg`/`.pfs`* é que seria preciso `pkg_pfs_tool`/`ps4_pfs_fuse` (MOUNT-06, opcional).

---

## 2. A criptografia (o ponto que custou o dia)

Todas as partições EAP usam **dm-crypt modo "plain"** com `aes-xts-plain64` e a chave EAP de
**32 bytes** (`eap_hdd_key.bin`).

### 2.1 O IV offset — `iv_offset = (dev_no - 1) << 32`

Em **CUH-1100 e posteriores** (todo Baikal/CUH-2xxx) o IV **não** começa em 0: o número do setor
usado na construção do IV recebe um offset fixo derivado do **número da partição**:

```
iv_offset = (dev_no - 1) << 32
```

| Partição | Cálculo | iv_offset |
|----------|---------|-----------|
| `sda25` | `24 << 32` | `103079215104` |
| `sda27` | `26 << 32` | `111669149696` |
| `sda29` | `28 << 32` | `120259084288` |

Fonte: psdevwiki, *Mounting HDD in Linux* (seção *cmtab for some CUH-1100 and later models*).

### 2.2 ⚠️ `cryptsetup` NÃO consegue aplicar esse offset

Isto é a armadilha central:

- `--offset` / `--skip` do `cryptsetup` são **data offset** (onde começam os dados no device),
  **não** o offset do IV. Passar `--offset 111669149696` faz o `cryptsetup` abortar com
  *"Requested offset is beyond real size of device"* (o valor é do IV, não uma posição no disco).
- Abrir com `iv_offset = 0` (o que o script antigo fazia, "tweak relative") decifra **lixo**:
  nenhum magic aparece e `mount` falha com `bad superblock` / `bad magic number`.
- Conclusão: é preciso montar a tabela do dm-crypt **na mão**, com `dmsetup`:

```bash
KEY_HEX=$(xxd -p -c 256 /etc/ps4-keys/eap_hdd_key.bin | tr -d '\n')   # 64 caracteres hex
SECTORS=$(blockdev --getsz /dev/sda27)
IV_OFFSET=$(( (27 - 1) << 32 ))                            # 111669149696

dmsetup create -r ps4_sda27 --table \
  "0 $SECTORS crypt aes-xts-plain64 $KEY_HEX $IV_OFFSET /dev/sda27 0"
```

Campos da tabela: `início setores crypt cipher chave_hex iv_offset device data_offset`.
`dmsetup create -r` cria o mapping **read-only** de verdade (o `cryptsetup` chamava isso de
`readonly`).

### 2.3 Como saber que o IV está certo

O superbloco UFS2 fica em `0x10000` (bloco 65536) e o magic `0x19540119` em `0x1055C`:

```bash
dd if=/dev/mapper/ps4_sda27 bs=1 skip=66908 count=4 2>/dev/null | xxd
# correto: 1901 5419
```

E `blkid -p` deve dizer `TYPE="ufs" VERSION="2"`. Sem isso, o IV (ou a chave) está errado.

---

## 3. Cadeia de montagem

```
/dev/sda27 | sda29 (UFS2)   /dev/sda25 (vfat)
        │
        │ dmsetup (aes-xts-plain64, chave EAP 32 B, iv_offset=(dev_no-1)<<32, -r)
        ▼
/dev/mapper/ps4_sda27 | ps4_sda29 | ps4_sda25
        │
        │ mount ro (ufstype=ufs2 | vfat)
        ▼
/mnt/ps4_internal/sda27 | sda29 | sda25
```

### 3.1 Chave EAP (usuário final)

A chave é **do console do usuário** (não existe chave "universal"): cada PS4 tem a sua, e ela
decifra o HD daquele console. Nada de chave vai no git nem na imagem — quem instala é o dono.

- **Local canônico (rootfs):**

  ```
  /etc/ps4-keys/eap_hdd_key.bin      dono root, modo 600
  ```

  A pasta `/etc/ps4-keys/` (modo 700) é criada pelo `01-build-image-7.0.sh` com um `LEIA-ME.txt`
  apontando para este documento. O build **não** contém nenhum segredo.

- **Formatos aceitos** (o `monta_particao.sh` detecta sozinho):

  | Formato | Tamanho | Observação |
  |---|---|---|
  | binário cru do EAPDumper | 32 B | recomendado |
  | binário + `\n` | 33 B | tolerado (ex.: `cat chave; echo`) |
  | texto com 64 hex | 64 B + `\n` | um token isolado ou hex solto |
  | saída `.txt` do payload | qualquer | extrai o primeiro trecho de 64 hex |

- **Ordem de busca** (a primeira que existir vence): `$PS4_KEYS_FILE` → `$PS4_KEYS_DIR/eap_hdd_key.bin`
  → `$PS4_KEYS_DIR/ps4_keys.bin` → `$PS4_KEYS_DIR/eap_hdd_key.hex` → `$PS4_KEYS_DIR/eap_hdd_key.txt`
  → `/etc/ps4_keys.bin` (compat) → `/tmp/keys.bin` (compat, volátil).

- **Instalação a partir do PC** (PS4 ligado no Linux, SSH ativo):

  ```bash
  PS4_SSH_PASS=ps4 ./distro/scripts/provisiona-chave.sh ~/eap_hdd_key.bin --ssh root@192.168.6.128
  ```

  O script normaliza/valida a chave, grava com dono root e modo 600, confere o sha256
  e — por padrão — tenta montar o `sda27` para provar que a chave é a certa (`--no-verify` pula).
  Ele **não** imprime a chave, só o sha256.

- **Instalação direto no console:**

  ```bash
  sudo install -d -m 700 -o root -g root /etc/ps4-keys
  sudo install -m 600 -o root -g root eap_hdd_key.bin /etc/ps4-keys/eap_hdd_key.bin
  sudo systemctl restart ps4-automount.service
  ```

- **Instalação num rootfs montado no PC** (antes de gravar o HD):

  ```bash
  sudo ./distro/scripts/provisiona-chave.sh ~/eap_hdd_key.bin --rootfs /mnt/ps4_rootfs_7.0
  ```

- **Conferir sem tocar no HD:** `monta_particao.sh --check-key` mostra qual arquivo seria usado
  (e avisa se o modo não for 600).

- **Sem chave:** o boot é normal. O `ps4-automount.service` imprime **uma** mensagem amigável
  (apontando `/etc/ps4-keys/eap_hdd_key.bin`) e sai com 0 — não há erro nem `failed` no systemd.

- **Como obter:** payload `EAPDumper` no **Orbis** (GoldHEN) — build em
  [`../tools/ps4_hdd_tools/build_eapdumper.sh`](../tools/ps4_hdd_tools/build_eapdumper.sh), envio por
  [`ENVIO_DE_PAYLOADS.md`](ENVIO_DE_PAYLOADS.md) (`ps4_send_payload.sh`), recuperação por FTP (`:2121`).
  A cópia mantida neste PC é dupla: `.env.keys` na raiz do repo (gitignored, `EAP_HDD_KEY` em
  hex) e a pasta **`~/ps4-keys/`** (modo 700) com `eap_hdd_key.bin` (32 B), `eap_hdd_key.hex`,
  `LEIA-ME.txt` e `chaves-refutadas.txt` (ERK/PROD que **não** decifram). Se o console for
  trocado, a chave é outra — dump novo obrigatório.

- Chave do console de teste confirmada ao vivo (2026-11-13): sha256
  `990c1aa3b821c4aa9a9acb0d25127eb6d3227e5f97232ffd6eee5a4d9511c8bf`
  (a chave em si **não** é registrada aqui; está em `.env.keys` e no console).

- **Dump do kernel Orbis (`kmem_dump_1252.bin`, `0xae7ef0`):** ERK
  `7fcf0536…476af6` — cópia de debug/rodata, **NÃO** decifra (testada).

### 3.2 Montagem do filesystem

| Partição | Comando |
|----------|---------|
| `sda27`, `sda29` | `mount -t ufs -o ufstype=ufs2,ro,noatime,noexec /dev/mapper/ps4_sdaNN /mnt/ps4_internal/sdaNN` |
| `sda25` | `mount -t vfat -o ro,noatime,noexec /dev/mapper/ps4_sda25 /mnt/ps4_internal/sda25` |

O `monta_particao.sh` detecta o tipo com `blkid -p` e escolhe a opção certa.

---

## 4. Scripts

| Script | Função |
|--------|--------|
| `distro/monta_particao.sh` | **Script único de produção.** Calcula `iv_offset` de `(dev_no-1)<<32`, cria/recria o mapper via `dmsetup -r` (recria se o mapper existente tiver IV errado), detecta o FS com `blkid` e monta ro |
| `distro/desmonta_particao.sh` | Desmonta uma partição e remove o mapper (`dmsetup remove`, fallback `cryptsetup remove`) |
| `distro/desmonta_todas.sh` | Desmonta tudo em `/mnt/ps4_internal` e remove todos os mappers `ps4_*` (usado no `ExecStop`) |
| `distro/automount.sh` | Detecta o HD interno (`sda`/`sdb`), monta **27, 29 e 25** |
| `distro/scripts/ps4_crypt_mount.sh` | **Legado.** Não vai para o rootfs; apenas chama o `monta_particao.sh` |

### Uso manual

```bash
# Jogos/dados (UFS2, ~884 GiB)
sudo /usr/local/bin/monta_particao.sh /dev/sda27

# eap_user / update
sudo /usr/local/bin/monta_particao.sh /dev/sda29
sudo /usr/local/bin/monta_particao.sh /dev/sda25

# HD interno como sdb (quando o USB de boot é sda)
sudo /usr/local/bin/monta_particao.sh sdb27

# Desmontar
sudo /usr/local/bin/desmonta_particao.sh /dev/sda27
sudo /usr/local/bin/desmonta_todas.sh

# Diagnóstico: forçar iv_offset (ex.: 0) para comparar
sudo PS4_MOUNT_IV_OFFSET=0 /usr/local/bin/monta_particao.sh /dev/sda27
```

Variáveis: `PS4_KEYS_FILE`, `PS4_MOUNT_IV_OFFSET`, `PS4_MOUNT_OPTS`
(padrão `ro,noatime,noexec`).

---

## 5. Automatização no boot

O build (`01-build-image-7.0.sh`) instala:

- `/etc/systemd/system/ps4-automount.service` (oneshot, `RemainAfterExit=yes`)
  - `ExecStart=/usr/local/bin/automount.sh`
  - `ExecStop=/usr/local/bin/desmonta_todas.sh`
- Habilitado em `multi-user.target.wants`
- `/etc/udev/rules.d/99-ps4-disk-permissions.rules`: modo `0666` para `sda*`, `dm-*`, `mapper/ps4_*`
- `/etc/udev/rules.d/99-ps4-media.rules`: labels de udisks2 (`ps4_sda27`→UFS2 games, `ps4_sda29`,
  `ps4_sda25`). **`sda13` não entra** (não é montável).
- `/etc/sudoers.d/ps4-hdd`: `ps4 ALL=(ALL:ALL) NOPASSWD: ALL`

O `automount.sh` tolera a ausência do HD interno (`exit 0`), então o boot não trava.

> ⚠️ O rootfs **já gravado** no HD pode ter a versão antiga do serviço
> (`ExecStop=desmonta_particao.sh /dev/sda27`). Para atualizar sem rebuild:
> `install -m 755 monta_particao.sh automount.sh desmonta_*.sh /usr/local/bin/` e
> `sed -i 's|^ExecStop=.*|ExecStop=/usr/local/bin/desmonta_todas.sh|' /etc/systemd/system/ps4-automount.service && systemctl daemon-reload`.

---

## 6. Diagnóstico

```bash
# O que está montado
mount | grep ps4_internal
df -h /mnt/ps4_internal/*

# Mappers e o IV efetivamente aplicado (campo 6 da tabela)
ls -l /dev/mapper/ps4_*
sudo dmsetup table ps4_sda27

# Magic UFS2 em 0x1055C (esperado: 1901 5419)
sudo dd if=/dev/mapper/ps4_sda27 bs=1 skip=66908 count=4 2>/dev/null | xxd

# Tipo/versão detectados
sudo blkid -p /dev/mapper/ps4_sda27

# Erros de mount
dmesg | tail
```

Sintomas e causa:

| Sintoma | Causa provável |
|---------|----------------|
| `unknown filesystem type 'pfs'` / `bad magic number` | IV errado (mapper com `iv_offset=0`) → rode `desmonta_particao.sh` e monte de novo |
| `Requested offset is beyond real size of device` | usou `cryptsetup --offset <ivoffset>` (é data offset, não IV) |
| `ps4_sda13` decifra lixo | normal: `sda13` não é EAP/UFS2 (swap antigo) |
| Mount falha com IV certo em `sda9`–`sda12`/`sda19`/`sda31` | essas usam chave SAMU/versioned |

---

## 7. Regras

- **Nunca montar diretamente em `/mnt`** — usar `/mnt/ps4_internal/<part>`.
- Montagem é sempre **read-only** (`dmsetup -r` + `ro`); não há suporte de escrita ao UFS2 do Orbis.
- O HD interno é `sda` ou `sdb` dependendo de qual disco é o USB de boot — os scripts detectam.
- **Nunca** usar `cryptsetup --offset/--skip` para o IV offset (ver §2.2).
- Não montar `sda13`: não é filesystem.
