---
name: tweak-xts-nao-e-lba-absoluto-prova-pares-ab-2026-08-01
description: Prova por pares A/B de que o tweak XTS do HD do PS4 é relativo à partição, não o LBA absoluto — invalida ~1M de tentativas anteriores; bloqueador real é a derivação de chave.
metadata:
  type: project
---

# Tweak XTS NÃO é o LBA absoluto — prova pelos pares A/B (2026-08-01)

Primeiro teste feito com o **SATA interno funcional** (feature nova desta sessão), lendo
`/dev/sda` direto no Linux em vez de trabalhar com dumps de 8 MB copiados.

## A prova

Duas partições formam pares A/B redundantes (mesmo conteúdo, cópias para update):

| Par | starts (LBA 512B) | bytes idênticos | ponto de divergência |
|-----|-------------------|-----------------|----------------------|
| `sda9` / `sda10` | 1941694464 / 1939597312 | **262832** | `16427 × 16` (bloco AES) |
| `sda11` / `sda12` | 1945888768 / 1943791616 | **262816** | `16426 × 16` (bloco AES) |

Os pontos de divergência são **exatamente alinhados a blocos AES de 16 bytes** e **não** a
setores de 512 B — assinatura clássica de XEX/XTS (uma diferença de plaintext afeta só o
bloco de 16 B correspondente).

**Dedução:** se o tweak incorporasse o LBA absoluto, dois plaintexts idênticos gravados em
LBAs absolutos diferentes produziriam ciphertexts completamente diferentes já no byte 0.
Eles são byte-a-byte idênticos por 256 KB. Logo:

1. **O tweak é relativo ao início da partição (começa em 0)** — não é o LBA absoluto.
2. **Os pares A/B compartilham a mesma chave.**

## Impacto

Isso **invalida a premissa central** de toda a caça ao tweak de 2026-07-31 (~1.000.001
combinações varridas em torno do LBA absoluto `57147392` de `sda27`, ±500k, mais variantes
de 4K/byte-offset). Todo esse espaço de busca estava errado por construção.

Também invalida o estado dos mappers `dmsetup` que estavam vivos no PS4:
```
ps4_sda13: ... iv_offset=19398656   (= start absoluto)
ps4_sda27: ... iv_offset=114294784  (= 2 × start absoluto, erro adicional)
```
Ambos usam LBA absoluto; o do `sda27` ainda por cima usa o dobro do valor correto
(o start real é `57147392`, confirmado via `/sys/block/sda/sda27/start`).

## O bloqueador real agora: derivação de chave

Testada a chave EAP canônica (`edf3f4d3...`, obtida ao vivo via EAPDumper e validada) com
**tweak = 0 relativo** nas **14 partições**: entropia da saída fica em ~7.95 bits/byte em
todas (= aleatório, nenhuma decripta). Combinado com o achado de RE
`sceSblWrapHddEapPartitionKeyData` (ver [[servicecrypt-samu-hardware-crypto-2026-08-01]]),
o modelo consistente é:

- **tweak** = índice de setor relativo à partição, a partir de 0 ✅ (deduzido acima)
- **chave** = derivada por **tipo** de partição a partir da chave EAP, no SAMU ❌ (bloqueador)

O fato de `sda9`/`sda10` compartilharem chave (e `sda11`/`sda12` idem) mostra que a
derivação é indexada pelo **tipo** de partição, não pela posição física — batendo com a
tabela de 16 GUIDs já mapeada (`sda9`/`sda10` = índice 0, `sda11`/`sda12` = índice 5).

## Negativos registrados (para não repetir)

- **Gap de 256 MB antes da primeira partição** (LBA 0..524287): contém exatamente **674
  bytes não-zero**, todos dentro do GPT (setores 0..33). De LBA 34 em diante é zero
  absoluto. **Não há blob de chaves escondido ali.**
- `sda13` tem entropia RAW baixa (7.536, 11.6% de zeros) — mas é só esparsidade: o hexdump
  mostra regiões literalmente não gravadas (bytes 560..1023 zerados). Não é pista de
  decriptação.

## Próximo passo proposto (não executado)

Extrair as **chaves por partição já desembrulhadas da RAM do kernel Orbis**, em vez de
tentar derivá-las. O `g_crypt_create_provider` (`0xffffffffdc9a40d0`) guarda a chave usada
no softc do provider; com as partições montadas no Orbis, essas chaves estão em heap do
kernel. Mesma técnica do EAPDumper, mirando os softcs do GEOM_CRYPT a partir da struct
`g_class` já localizada (file offset `0x1afa940`). Exige boot no Orbis + payload — decisão
do usuário.

Ferramenta criada: `consolidado/tools/ps4_partition_crypto_survey.py` (varredura de
entropia + tweaks por partição). Registro em `test_history` id **79**.
