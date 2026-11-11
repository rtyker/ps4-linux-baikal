---
name: servicecrypt-samu-hardware-crypto-2026-08-01
description: Engenharia reversa revela que GEOM_CRYPT utiliza o subsistema ServiceCryptAsync para offloading criptográfico via coprocessador SAMU no PS4
metadata:
  type: project
---

# Descoberta de Engenharia Reversa: Subsistema `ServiceCryptAsync` / SAMU em GEOM_CRYPT (2026-08-01)

## Resumo
A análise detalhada de strings e descompilação no dump do kernel Orbis (`memoriateste.bin` / `kmem_dump_1252.bin`) revelou o subsistema de criptografia de alto nível utilizado pelo `GEOM_CRYPT`: **`ServiceCrypt`** / **`ServiceCryptAsync`**.

## Mapeamento de Offsets
- `0xaee3d3`: `GEOM_CRYPT[%u]: ServiceCrypt error %d`
- `0xaeeb94`: `GEOM_CRYPT[%u]: ServiceCryptAsync error %d`
- `0xb16862`: `ServiceCryptAsync() failed 0x%x`
- `0xaeb434`: `sceSblWrapHddEapPartitionKeyData`
- `0xae8bc5`: `sceSblKeymgrSmCallfuncWithID`

## Arquitetura Criptográfica do Orbis OS
1. **Offloading por Hardware:** No PS4, o driver de sistema de arquivos do kernel Orbis não executa decriptação XTS-AES via software na CPU Jaguar.
2. **Submissão I/O:** Cada operação de I/O de leitura/escrita enviada ao `GEOM_CRYPT` é repassada para a rotina `ServiceCryptAsync(request, key_id, lba_offset)`.
3. **Mailbox SAMU / SBL:** O `ServiceCryptAsync` envia o comando criptográfico para o coprocessador **SAMU (Secure Asset Management Unit)** via caixa de correio BPCIE/SBL (`sceSblKeymgrSmCallfuncWithID`), utilizando slots de chave gravados na memória segura no boot.
4. **Implicação para o Linux:** O `cryptsetup` do Linux em modo software puro (`plain`) usando a chave EAP flat não decripta as partições PFS diretamente porque o coprocessador SAMU aplica o unwrap de chave por partição (`sceSblWrapHddEapPartitionKeyData`).
