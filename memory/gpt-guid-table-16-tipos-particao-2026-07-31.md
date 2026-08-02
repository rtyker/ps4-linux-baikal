---
name: gpt-guid-table-16-tipos-particao-2026-07-31
description: Tabela hardcoded de 16 GUIDs de tipo de partição achada no kernel Orbis (memoriateste.bin offset 0x1a6d800) — sda13 é índice 6, sda27 é índice 13
metadata:
  type: project
---

O disco interno do PS4 usa **GPT real** (`fdisk -l /dev/sda` → `Disklabel type: gpt`),
não um formato APA proprietário simples. Isso permite ler as entradas GPT brutas
(128 bytes cada, array em byte 1024, entrada N = byte `1024 + (N-1)*128`) via SSH
read-only.

O campo GPT `Attributes` (offset 0x30 da entrada, 8 bytes) está **zerado** tanto em
`sda13` quanto em `sda27` — não é daí que vem a flag de seleção de chave usada por
`g_crypt_create_provider` (ver [[geom-crypt-flag-origin-beco-sem-saida-2026-07-31]]).

Busca binária direta pelos Type GUIDs das duas partições dentro de
`consolidado/memoriateste.bin` achou ambos a 0x70 bytes de distância um do outro —
parte de um array compacto de **16 GUIDs de 16 bytes, sem gaps**, no file offset
`0x1a6d800`-`0x1a6d900`:

```
#6  (sda13, System 12G):     76a9a5b4-44b0-472a-bde3-3107472adee2
#13 (sda27, Games/user 897.6G): c638477a-e002-4b57-a454-a27fb63a33a8
```

(lista completa dos 16 GUIDs no `PLANO_INVESTIGACAO_CHAVE_PFS_SDA_2026-07-30.md`
Seção 11).

**Why:** é quase certamente a tabela de lookup do kernel que mapeia GPT type-GUID →
índice/papel de partição (0-15) — o índice provavelmente é usado para derivar a flag
de seleção de chave (`+0x70`), não lido diretamente do disco. Confirmar as 14 GUIDs
restantes lendo as entradas GPT das outras partições do PS4 (`sda1,3,5,7,9,10,11,12,
17,19,25,29`) e comparando com esta tabela mapearia todas as 16 categorias.

**How to apply:** para achar o código que LÊ essa tabela (e assim a lógica que decide
o tipo de chave por índice), busca de ponteiro literal de 8 bytes e busca de `LEA`
RIP-relative na região executável de `memoriateste.bin` deram **zero resultados** —
essa captura parcial provavelmente não contém o código de bring-up/taste do GEOM_CRYPT.
Precisa de análise completa do Ghidra (Rota A, custo ~15-30min) ou um dump de memória
mais abrangente. Scripts usados: `consolidado/tools/find_guid_table_xrefs.py`.

**Nota técnica para reutilizar os scripts PyGhidra:** endereços de kernel
(`>=0x8000000000000000`) vêm do JPype/PyGhidra como `long` **assinado** — sempre
corrigir com `if addr < 0: addr += 1 << 64` antes de fazer aritmética de endereço em
Python, senão a soma/subtração de offsets dá resultado errado silenciosamente.
