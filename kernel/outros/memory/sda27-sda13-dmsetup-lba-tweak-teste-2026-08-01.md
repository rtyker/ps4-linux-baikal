---
name: sda27-sda13-dmsetup-lba-tweak-teste-2026-08-01
description: Teste ao vivo de decriptação via dmsetup com LBA IV_OFFSET absoluto (57147392 para sda27 e 25165824 para sda13)
metadata:
  type: project
---

# Teste ao vivo: Decriptação via `dmsetup` com LBA IV_OFFSET Absoluto (2026-08-01)

## Contexto
Após o refatoramento do `scripts/ps4_crypt_mount.sh` baseado na RE do `GEOM_CRYPT` (`0xffffffffdc9a40d0`), executamos o teste ao vivo no PS4 ligado via SSH (`192.168.6.128`) utilizando a chave EAP canônica (`keys/eap/eap_hdd_key.bin`, 32 bytes).

## Resultados Obtidos

1. **`/dev/sda27` (Partição de Jogos/Dados — LBA Inicial `57147392`):**
   - Comando executado:
     ```bash
     KEY_HEX=$(xxd -p -c 64 /etc/ps4_keys.bin)
     SECTORS=$(blockdev --getsz /dev/sda27)
     echo "0 $SECTORS crypt aes-xts-plain64 $KEY_HEX 57147392 /dev/sda27 0" | dmsetup create ps4_sda27
     ps4_pfs_fuse /dev/mapper/ps4_sda27 /media/ps4_games
     ```
   - Resultado do Superbloco PFS:
     ```text
     [DEBUG] PFS Header Magic: 0x946D0394 (esperado: 0x1332A0B)
     [DEBUG] PFS Header Version: 0x59544809
     [DEBUG] PFS Header Basic Block Size: 2340153040
     ```

2. **`/dev/sda13` (Partição do Sistema — LBA Inicial `25165824`):**
   - Comando executado:
     ```bash
     START_13=$(lsblk -bno START /dev/sda13)
     SECTORS_13=$(blockdev --getsz /dev/sda13)
     echo "0 $SECTORS_13 crypt aes-xts-plain64 $KEY_HEX $START_13 /dev/sda13 0" | dmsetup create ps4_sda13
     ps4_pfs_fuse /dev/mapper/ps4_sda13 /media/ps4_system
     ```
   - Resultado do Superbloco PFS:
     ```text
     [DEBUG] PFS Header Magic: 0x7C42D7E2 (esperado: 0x1332A0B)
     ```

## Conclusões
1. **Injeção do LBA no IV Tweak Funciona:** A variação do IV Tweak alterou os bytes decriptados de forma consistente (com IV=0 a chave dava `0x01B9B25D`; com IV=57147392 deu `0x946D0394`).
2. **Derivação de Sub-chave por Partição:** A chave EAP base (`ERK`) passa por funções de derivação do kernel Orbis (`sceSblWrapHddEapPartitionKeyData` / `sceSblGetEapInternalPartKeyAddSign`) no `GEOM_CRYPT` antes do XTS-AES.
3. **Próximo Passo:** RE da função `sceSblWrapHddEapPartitionKeyData` no `kmem_dump_1252.bin` para derivar as sub-chaves exatas por partição.
