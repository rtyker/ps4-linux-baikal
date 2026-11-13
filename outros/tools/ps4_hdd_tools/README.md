# Suíte de Utilitários de Montagem do HD do PS4 (`tools/ps4_hdd_tools/`)

Gama de ferramentas para decriptação, inspeção de GPT e verificação de superbloco UFS2/PFS do HD interno do PS4.

---

## Estrutura dos Utilitários

| Script | Função | Exemplo de Uso |
|---|---|---|
| [`ps4_eap_key_extractor.py`](ps4_eap_key_extractor.py) | Extrai a chave ERK (32 bytes) do rótulo `SCE_EAP_HDD__KEY` em dumps de NOR/memória Orbis. | `python3 ps4_eap_key_extractor.py consolidado/memoriateste.bin /etc/ps4-keys/eap_hdd_key.bin` |
| [`ps4_gpt_partition_inspector.py`](ps4_gpt_partition_inspector.py) | Lê a tabela GPT, compara os Type GUIDs com os 16 GUIDs oficiais do Orbis e calcula os LBAs. | `python3 ps4_gpt_partition_inspector.py /dev/sda` |
| [`ps4_cmtab_generator.py`](ps4_cmtab_generator.py) | Gera `/etc/cryptmount/cmtab` (e o equivalente em `dmsetup`) com `ivoffset = (dev_no-1)<<32` para `sda25`/`sda27`/`sda29`. | `python3 ps4_cmtab_generator.py sda /etc/ps4-keys/eap_hdd_key.bin` |
| [`ps4_pfs_magic_checker.py`](ps4_pfs_magic_checker.py) | Valida o magic **UFS2** (`0x19540119` em `0x1055C`) no dispositivo já decifrado. | `python3 ps4_pfs_magic_checker.py /dev/mapper/ps4_sda27` |
| [`monta_particao.sh`](../../../distro/monta_particao.sh) | **Script de produção:** aplica o `iv_offset` via `dmsetup -r`, detecta o FS e monta read-only. | `sudo distro/monta_particao.sh /dev/sda27` |
| [`build_eapdumper.sh`](build_eapdumper.sh) | Compila o payload **EAPDumper** (obtém a chave EAP do HD a partir do Orbis). | `./build_eapdumper.sh` |

---

## EAPDumper — obter a chave EAP (payload Orbis)

A chave **não** existe no repositório (`keys/` é gitignored) e **não** é extraível do Linux rodando
(kernel sem `CONFIG_MTD`/`CONFIG_SPI`, e o `baikal-memory.ko` não expõe a SPM de forma utilizável).
A única via é rodar o payload **no Orbis, antes do kexec**, com GoldHEN ≥ v2.4b18.8.

- **Projeto de terceiros** (não nosso): <https://github.com/seregonwar/EAPDumper> — MIT, autor `seregonwar`.
- Clone local: `outros/tools/ps4_hdd_tools/EAPDumper/` (commit `d590c3b`, tag `v0.2.0` = `b97e943`).
- Toolchain: [ps4-payload-sdk](https://github.com/ps4-payload-dev/sdk) v0.9 (John Törnblom) extraído em
  `EAPDumper/ps4-payload-sdk` (gitignored) + LLVM ≥ 18 no host.

### Build

```bash
./outros/tools/ps4_hdd_tools/build_eapdumper.sh
# gera EAPDumper/EAPDumper.bin e EAPDumper/EAP-Scanner.bin (~83 KB cada)
# build reprodutível: sha256 52e6617ee5ceff727a807c8a3ba925cc5d5fffeff3fd770dad1d76fb5975eb0f
```

> O Makefile do projeto **não exporta** `PS4_PAYLOAD_SDK`, mas o wrapper `orbis-ld` precisa dela para
> achar `ldscripts/elf_x86_64.x`. Por isso `make` puro falha com
> `cannot find linker script /ldscripts/elf_x86_64.x` — use o script acima (ou passe a variável).
>
> Ao copiar o SDK, use `unzip`/`cp -a`: `cp -r` dereferencia os symlinks de `bin/` e quebra o toolchain.

### O que o payload faz

1. Lê a chave da memória do kernel Sony no offset conhecido do firmware (`EAP_OFFSETS`, FW 5.03–12.02).
   **FW 12.52 não está na tabela** → cai no *sniper scan* cego em `0x2600000`–`0x2900000`
   (cobre `0x26C4CF0`, o offset correto da família 12.x).
2. Inverte os blocos de 16 bytes (`reverse_16_byte_blocks`) — o kernel guarda a chave com os bytes
   trocados; a chave **gravada já é a utilizável** pelo `cryptsetup`.
3. Fallback de arquivo: `/system_data/priv/eap/eap_hdd_key.bin`, depois `/eap_user/eap_hdd_key.bin`.
4. Grava `/data/hddeap/eap_hdd_key.{bin,hex,txt}` (obrigatório) e `/mnt/usb0/eap_hdd_key.{bin,hex,txt}`.

### Como executar no PS4

**Procedimento canônico: [`../../docs/ENVIO_DE_PAYLOADS.md`](../../docs/ENVIO_DE_PAYLOADS.md).**
Resumo (PS4 no **Orbis** com GoldHEN ativo):

```bash
# 1) valida (não envia nada)
./outros/scripts/ps4_send_payload.sh --check outros/tools/ps4_hdd_tools/EAPDumper/EAPDumper.bin

# 2) envia pelo BinLoader do GoldHEN (:9090)
./outros/scripts/ps4_send_payload.sh outros/tools/ps4_hdd_tools/EAPDumper/EAPDumper.bin

# 3) recupera a chave pelo FTP do GoldHEN (:2121), sem tirar o HD
./outros/scripts/ps4_send_payload.sh --ftp-get /data/hddeap/eap_hdd_key.bin
```

Alternativa sem rede: copiar o `.bin` para um pendrive e carregar pelo menu **Payloads** do GoldHEN.

⚠️ Não testar a porta 9090 com `nc -z`/`telnet` (o BinLoader aceita **uma** conexão por sessão).
`9020/9021` é o `elfldr` do `ps4-payload-dev`, não o GoldHEN.

Depois é só provisionar em `/etc/ps4-keys/eap_hdd_key.bin` no rootfs Linux (32 bytes binários, modo `0600`).

---

## Fluxo de Teste Recomendado

1. **Passo 1 — Obtenção de Chave (no Orbis, antes do kexec):**
   ```bash
   ./outros/tools/ps4_hdd_tools/build_eapdumper.sh
   ./outros/scripts/ps4_send_payload.sh outros/tools/ps4_hdd_tools/EAPDumper/EAPDumper.bin
   ./outros/scripts/ps4_send_payload.sh --ftp-get /data/hddeap/eap_hdd_key.bin
   # depois: copiar eap_hdd_key.bin para /etc/ps4-keys/eap_hdd_key.bin no rootfs Linux
   ```
   Procedimento completo de injeção: [`../../docs/ENVIO_DE_PAYLOADS.md`](../../docs/ENVIO_DE_PAYLOADS.md).
   > O `ps4_eap_key_extractor.py` **não** serve para isso: ele só varre dumps (`memoriateste.bin`,
   > `kmem_dump_1252.bin`) e o que ele acha nesses dumps é a cópia de debug/rodata
   > (`7fcf0536…`), que **não decripta** as partições.

2. **Passo 2 — Mapeamento do HD:**
   ```bash
   python3 tools/ps4_hdd_tools/ps4_gpt_partition_inspector.py /dev/sda
   ```

3. **Passo 3 — Mapeamento criptográfico + mount (script de produção):**
   ```bash
   sudo distro/monta_particao.sh /dev/sda27      # user     (UFS2)
   sudo distro/monta_particao.sh /dev/sda29      # eap_user (UFS2)
   sudo distro/monta_particao.sh /dev/sda25      # update   (FAT32)
   ```
   O `iv_offset` é `(dev_no - 1) << 32` e precisa ser aplicado via `dmsetup` —
   o `cryptsetup` não tem opção para isso (`--offset`/`--skip` são data offset).
   Detalhes: [`../../docs/MONTAGEM_HD_INTERNO.md`](../../docs/MONTAGEM_HD_INTERNO.md) §2.

4. **Passo 4 — Validação do magic UFS2:**
   ```bash
   python3 outros/tools/ps4_hdd_tools/ps4_pfs_magic_checker.py /dev/mapper/ps4_sda27
   # ou, na mão: dd if=/dev/mapper/ps4_sda27 bs=1 skip=66908 count=4 2>/dev/null | xxd
   # esperado: 1901 5419
   ```
