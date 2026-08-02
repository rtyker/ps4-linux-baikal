# Base do Kernel 12.52 Resolvida = `0xffffffffdc350000` + EAPDumper salvo nos payloads (2026-07-31)

## Resumo

Sessão de registro/fechamento da investigação da chave PFS/EAP do HD interno. A principal
descoberta nova é a **base do kernel Orbis 12.52 no dump**: `0xffffffffdc350000` (NÃO
`0xffffffffdc000000` como se supunha anteriormente). Isso fecha a dúvida da Seção 21.3 do
`PLANO_INVESTIGACAO_CHAVE_PFS_SDA_2026-07-30.md`.

## Descoberta 1 — Base do kernel = `0xffffffffdc350000`

3 provas independentes convergem:

1. **`lea` no `amd64_syscall`:** a instrução `lea` em file offset `0x72446`
   (RIP = `0x7244d`, displacement `0xfff8dd73` = −`0x7228d`) resolve para
   file offset `0x1c0` = `amd64_syscall` (xfast_syscall do FreeBSD 12.52).
   `freebsd-headers/ps4-offsets/1250.h` define `kernel_offset_xfast_syscall 0x1c0`
   para 12.52 — o `amd64_syscall` precisa estar na mesma base do dump.
2. **Consistência offset ↔ VA absoluto:** `g_crypt_create_provider` decompilado
   (`consolidado/decompiled/geom_crypt/decompiled_dc9a40d0_g_crypt_create.c:52`) faz
   `bcopy((void*)0xffffffffdea14cf0, puVar6+10, 0x20)`. E
   `0xffffffffdc350000 + 0x26C4CF0 = 0xffffffffdea14cf0` — onde `0x26C4CF0` é o
   `kern_off_eap_hdd_key` do magic.h para 12.50/12.52. Perfeito encaixe.
3. **Coerência ELF:** `e_entry` está em file offset `0x6a410`, logo
   `base = e_entry − 0x6a410 = 0xffffffffdc350000`.

### Consequência crítica (fecha Seção 21.3)

O VA `0xffffffffdea14cf0` (chave EAP lida pelo kernel) cai no **BSS do segmento 4** do dump:
file offset `0x1ec4cf0` > filesz (`0x13265e8`). O dump `kmem_dump_1252.bin`/`memoriateste.bin`
**não populou o BSS** — por isso os bytes são zeros. **A chave EAP real não existe neste dump**
(e não porque "foi apagada da RAM").

Consequência: o ERK `7fcf0536d3b5f5bd09a5d7b3833f868bbe1f6d90803b4f54029e6265f6476af6` extraído
de file `0xae7ef0` (VA `0xffffffffdce37ef0`, label `SCE_EAP_HDD__KEY`) é uma **cópia de
debug/rodata**, NÃO necessariamente o buffer ativo lido pelo `g_crypt_create_provider`. Ou seja:
a chave real só sai de um dump com RAM viva no momento certo, ou do EAPDumper ao vivo.

## Descoberta 2 — EAPDumper v0.2.0 salvo na pasta de payloads

- Cópia: `ps4-linux-payloads/EAPDumper.bin` (83504 bytes).
- SHA-256: `73f9306da119606cde4ccd93fa0496ba4de0ec00b4850565e7b1889c84422972` (idêntico ao
  de `tools/ps4_hdd_tools/EAPDumper/EAPDumper.bin`).
- **FW 12.52 (0x12500000/0x12520000) NÃO está na tabela fast-path** do EAPDumper
  (confirmação via `rg` em `main.c`): para 12.50/12.52 cai no **scanner cego** que varre
  `0x2600000`–`0x2900000` em passos de 16 (cobre `0x26C4CF0`), com entropia + heurísticas
  (NEIGHBOR_WINDOW=32, POST_KEY_WINDOW=32) e já aplica `reverse_16_byte_blocks` ao salvar
  `/data/hddeap/eap_hdd_key.{bin,hex,txt}` e `/mnt/usb0/`.
- Bases: `KERNEL_ADDRESS_IMAGE_BASE + offset`. Se o SDK usar base `0xffffffffdc000000`, o
  scanner cego ainda encontra a chave pois varre o range de offsets — não depende da base estar
  certa, só da memória viva estar acessível.

## Impacto nos próximos passos

1. EAPDumper continua sendo o caminho canônico para obter a chave EAP real (boot Orbis 12.52 +
   GoldHEN + payloader na porta 9090, coletar `/data/hddeap/eap_hdd_key.bin`, testar rev16 nos
   scripts XTS locais).
2. Qualquer nova captura de dump do kernel Orbis deve ser feita com a chave ainda na RAM
   (janela durante o boot/pós-boot antes do kexec) para capturar o VA `0xffffffffdea14cf0`
   populado.

## Arquivos

- `PLANO_INVESTIGACAO_CHAVE_PFS_SDA_2026-07-30.md` Seção 21.3 (reescrita com a causa raiz).
- `consolidado/decompiled/geom_crypt/decompiled_dc9a40d0_g_crypt_create.c:52` (bcopy da chave).
- `ps4-linux-payloads/EAPDumper.bin` (binário salvo, sha256 `73f9306d...`).
- `ps4-linux-payloads/freebsd-headers/ps4-offsets/1250.h` (`kernel_offset_xfast_syscall 0x1c0`).
- `ps4-linux-payloads/linux/magic.h` (`kern_off_eap_hdd_key 0x26c4cf0`, 12.50/12.52).
