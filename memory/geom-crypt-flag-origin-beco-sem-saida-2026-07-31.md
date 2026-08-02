---
name: geom-crypt-flag-origin-beco-sem-saida-2026-07-31
description: Tentativa de RE automatizada (PyGhidra headless) para achar a função que popula a flag +0x70 usada por g_crypt_create_provider esgotou-se sem análise completa do Ghidra
metadata:
  type: project
---

Seguindo a RE de `g_crypt_create_provider` (`0xffffffffdc9a40d0`, ver
[[sda27-decriptacao-magic-incorreto-2026-07-30]] e
`PLANO_INVESTIGACAO_CHAVE_PFS_SDA_2026-07-30.md` Seção 9), tentei rastrear
automaticamente (BFS de callers via PyGhidra headless em Docker) a função que
**popula** a flag de seleção de chave (offset `+0x70` de uma struct alcançada
a partir do provider GEOM) — essa flag decide se a partição usa a chave EAP
(bytes crus, decriptável em software) ou um ID de chave residente em
hardware/SAMU (`0x30`/`0x31`/`0x32`/`0x35`, não decriptável em software).

**Resultado: beco sem saída, 3 tentativas na Seção 10 do plano.** O endereço
`0xffffffffdc9a3de7` (citado como "caller confirmado" na Seção 9) na
verdade é um endereço NO MEIO da função `0xffffffffdc9a3750` (função de
refcount/cleanup do provider, não relacionada à flag) — o achado anterior de
"caller confirmado" é duvidoso, possível artefato de decompilação malformada
(função criada em endereço que não é boundary real). Busca de referências de
dados cruas (ponteiro literal de 8 bytes) às duas funções também deu zero
resultados em `memoriateste.bin`.

**Why:** GEOM class ops (`taste`/`start`/`access`/`orphan`/`destroy`) são
chamadas via ponteiro de função em `struct g_class`, não por `CALL` direto —
não são localizáveis por busca simples de string→xref ou por scan de
ponteiro literal num dump parcial sem análise completa do Ghidra
(`-noanalysis` foi usado propositalmente em todas as extrações desta sessão
para evitar os 15+ min de `DecompilerParameterID`).

**How to apply:** não insistir em mais RE cega (string→xref→decomp) neste
dump sem rodar análise completa do Ghidra primeiro (custo ~15-30 min,
Rota A no plano). **Rota B (recomendada): ler os bytes crus do header APA
on-disk de `sda13` e `sda27` diretamente via SSH no PS4 real** — já se sabe
exatamente quais bits da flag (26/29/30/31) selecionam qual chave, só falta
achar o offset do campo de flags dentro do header APA (formato já
parcialmente documentado pela comunidade de jailbreak) e comparar o valor
real entre as duas partições. Ver `PLANO_INVESTIGACAO_CHAVE_PFS_SDA_2026-07-30.md`
Seção 10 para o registro completo.
