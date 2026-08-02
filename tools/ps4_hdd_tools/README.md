# Suíte de Utilitários de Montagem do HD do PS4 (`tools/ps4_hdd_tools/`)

Gama de ferramentas para decriptação, inspeção de GPT e verificação de superbloco UFS2/PFS do HD interno do PS4.

---

## Estrutura dos Utilitários

| Script | Função | Exemplo de Uso |
|---|---|---|
| [`ps4_eap_key_extractor.py`](file:///mnt/t/downloads/PS4/linux_project/tools/ps4_hdd_tools/ps4_eap_key_extractor.py) | Extrai a chave ERK (32 bytes) do rótulo `SCE_EAP_HDD__KEY` em dumps de NOR/memória Orbis. | `python3 ps4_eap_key_extractor.py consolidado/memoriateste.bin /etc/ps4_keys.bin` |
| [`ps4_gpt_partition_inspector.py`](file:///mnt/t/downloads/PS4/linux_project/tools/ps4_hdd_tools/ps4_gpt_partition_inspector.py) | Lê a tabela GPT, compara os Type GUIDs com os 16 GUIDs oficiais do Orbis e calcula os LBAs. | `python3 ps4_gpt_partition_inspector.py /dev/sda` |
| [`ps4_cmtab_generator.py`](file:///mnt/t/downloads/PS4/linux_project/tools/ps4_hdd_tools/ps4_cmtab_generator.py) | Gera o arquivo de configuração `/etc/cryptmount/cmtab` com os `ivoffset` absolutos para `cryptmount`. | `python3 ps4_cmtab_generator.py /dev/sda /etc/ps4_keys.bin` |
| [`ps4_pfs_magic_checker.py`](file:///mnt/t/downloads/PS4/linux_project/tools/ps4_hdd_tools/ps4_pfs_magic_checker.py) | Checa se o dispositivo decriptado possui o magic number UFS2 (`0x1332A0B`). | `python3 ps4_pfs_magic_checker.py /dev/mapper/ps4_sda13` |
| [`scripts/ps4_crypt_mount.sh`](file:///mnt/t/downloads/PS4/linux_project/scripts/ps4_crypt_mount.sh) | Runner principal que aplica `--skip <LBA>` e realiza o `cryptsetup create` read-only. | `bash scripts/ps4_crypt_mount.sh /dev/sda13 /mnt/ps4_system` |

---

## Fluxo de Teste Recomendado

1. **Passo 1 — Extração de Chave:**
   ```bash
   python3 tools/ps4_hdd_tools/ps4_eap_key_extractor.py consolidado/memoriateste.bin /etc/ps4_keys.bin
   ```

2. **Passo 2 — Mapeamento do HD:**
   ```bash
   python3 tools/ps4_hdd_tools/ps4_gpt_partition_inspector.py /dev/sda
   ```

3. **Passo 3 — Mapeamento Criptográfico:**
   ```bash
   sudo bash scripts/ps4_crypt_mount.sh /dev/sda13
   ```

4. **Passo 4 — Validação de Magic UFS2:**
   ```bash
   python3 tools/ps4_hdd_tools/ps4_pfs_magic_checker.py /dev/mapper/ps4_sda13
   ```
